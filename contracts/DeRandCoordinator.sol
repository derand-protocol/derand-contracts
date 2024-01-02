// SPDX-License-Identifier: MIT
pragma solidity ^0.8.4;

import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {DeRandCoordinatorInterface} from "./interfaces/DeRandCoordinatorInterface.sol";
import {DeRandConsumerBase} from "./DeRandConsumerBase.sol";
import "./interfaces/IMuonClient.sol";
import "hardhat/console.sol";

contract DeRandCoordinator is Ownable, DeRandCoordinatorInterface {
    uint256 public muonAppId;
    IMuonClient.PublicKey public muonPublicKey;
    IMuonClient public muon;

    // Note a nonce of 0 indicates consumer has not made a request yet.
    mapping(address => uint64) /* consumer */ /* nonce */ private s_consumers;

    // Set this maximum to 200 to give us a 56 block window to fulfill
    // the request before requiring the block hash feeder.
    uint16 public constant MAX_REQUEST_CONFIRMATIONS = 200;
    uint32 public constant MAX_NUM_WORDS = 500;
    // 5k is plenty for an EXTCODESIZE call (2600) + warm CALL (100)
    // and some arithmetic operations.
    uint256 private constant GAS_FOR_CALL_EXACT_CHECK = 5_000;
    error InvalidRequestConfirmations(uint16 have, uint16 min, uint16 max);
    error GasLimitTooBig(uint32 have, uint32 want);
    error NumWordsTooBig(uint32 have, uint32 want);
    error NoCorrespondingRequest();
    error IncorrectCommitment();
    error Reentrant();
    struct RequestCommitment {
        uint256 blockNum;
        uint32 callbackGasLimit;
        uint32 numWords;
        address sender;
    }
    mapping(uint256 => bytes32) /* requestID */ /* commitment */
        private s_requestCommitments;
    event RandomWordsRequested(
        uint256 requestId,
        uint256 preSeed,
        uint16 minimumRequestConfirmations,
        uint32 callbackGasLimit,
        uint32 numWords,
        address indexed sender
    );
    event RandomWordsFulfilled(
        uint256 indexed requestId,
        address indexed consumer,
        uint256 outputSeed,
        bool success
    );

    struct Config {
        uint16 minimumRequestConfirmations;
        uint32 maxGasLimit;
        // Reentrancy protection.
        bool reentrancyLock;
    }
    Config private s_config;
    event ConfigSet(uint16 minimumRequestConfirmations, uint32 maxGasLimit);

    constructor(
        uint256 _muonAppId,
        IMuonClient.PublicKey memory _muonPublicKey,
        address _muon
    ) Ownable(msg.sender) {
        muonAppId = _muonAppId;
        muonPublicKey = _muonPublicKey;
        muon = IMuonClient(_muon);
    }

    /**
     * @notice Sets the configuration of the coordinator
     * @param minimumRequestConfirmations global min for request confirmations
     * @param maxGasLimit global max for request gas limit
     */
    function setConfig(
        uint16 minimumRequestConfirmations,
        uint32 maxGasLimit
    ) external onlyOwner {
        if (minimumRequestConfirmations > MAX_REQUEST_CONFIRMATIONS) {
            revert InvalidRequestConfirmations(
                minimumRequestConfirmations,
                minimumRequestConfirmations,
                MAX_REQUEST_CONFIRMATIONS
            );
        }
        s_config = Config({
            minimumRequestConfirmations: minimumRequestConfirmations,
            maxGasLimit: maxGasLimit,
            reentrancyLock: false
        });
        emit ConfigSet(minimumRequestConfirmations, maxGasLimit);
    }

    function getConfig()
        external
        view
        returns (uint16 minimumRequestConfirmations, uint32 maxGasLimit)
    {
        return (s_config.minimumRequestConfirmations, s_config.maxGasLimit);
    }

    /**
     * @inheritdoc DeRandCoordinatorInterface
     */
    function getRequestConfig()
        external
        view
        override
        returns (uint16, uint32)
    {
        return (s_config.minimumRequestConfirmations, s_config.maxGasLimit);
    }

    /**
     * @inheritdoc DeRandCoordinatorInterface
     */
    function requestRandomWords(
        bytes32 keyHash,
        uint64 subId,
        uint16 requestConfirmations,
        uint32 callbackGasLimit,
        uint32 numWords
    ) external override nonReentrant returns (uint256) {
        // Note: a nonce of 0 indicates consumer has not made a request yet.
        uint64 currentNonce = s_consumers[msg.sender];

        // Input validation using the config storage word.
        if (
            requestConfirmations < s_config.minimumRequestConfirmations ||
            requestConfirmations > MAX_REQUEST_CONFIRMATIONS
        ) {
            revert InvalidRequestConfirmations(
                requestConfirmations,
                s_config.minimumRequestConfirmations,
                MAX_REQUEST_CONFIRMATIONS
            );
        }
        // No lower bound on the requested gas limit. A user could request 0
        // and they would simply be billed for the proof verification and wouldn't be
        // able to do anything with the random value.
        if (callbackGasLimit > s_config.maxGasLimit) {
            revert GasLimitTooBig(callbackGasLimit, s_config.maxGasLimit);
        }
        if (numWords > MAX_NUM_WORDS) {
            revert NumWordsTooBig(numWords, MAX_NUM_WORDS);
        }

        uint64 nonce = currentNonce + 1;
        (uint256 requestId, uint256 preSeed) = _computeRequestId(
            msg.sender,
            nonce
        );

        s_requestCommitments[requestId] = keccak256(
            abi.encode(
                requestId,
                block.number,
                callbackGasLimit,
                numWords,
                msg.sender
            )
        );
        emit RandomWordsRequested(
            requestId,
            preSeed,
            requestConfirmations,
            callbackGasLimit,
            numWords,
            msg.sender
        );
        s_consumers[msg.sender] = nonce;

        return requestId;
    }

    /**
     * @notice Get request commitment
     * @param requestId id of request
     * @dev used to determine if a request is fulfilled or not
     */
    function getCommitment(uint256 requestId) external view returns (bytes32) {
        return s_requestCommitments[requestId];
    }

    function _computeRequestId(
        address sender,
        uint64 nonce
    ) private pure returns (uint256, uint256) {
        uint256 preSeed = uint256(keccak256(abi.encode(sender, nonce)));
        return (uint256(keccak256(abi.encode(preSeed))), preSeed);
    }

    /**
     * @dev calls target address with exactly gasAmount gas and data as calldata
     * or reverts if at least gasAmount gas is not available.
     */
    function _callWithExactGas(
        uint256 gasAmount,
        address target,
        bytes memory data
    ) private returns (bool success) {
        assembly {
            let g := gas()
            // Compute g -= GAS_FOR_CALL_EXACT_CHECK and check for underflow
            // The gas actually passed to the callee is min(gasAmount, 63//64*gas available).
            // We want to ensure that we revert if gasAmount >  63//64*gas available
            // as we do not want to provide them with less, however that check itself costs
            // gas.  GAS_FOR_CALL_EXACT_CHECK ensures we have at least enough gas to be able
            // to revert if gasAmount >  63//64*gas available.
            if lt(g, GAS_FOR_CALL_EXACT_CHECK) {
                revert(0, 0)
            }
            g := sub(g, GAS_FOR_CALL_EXACT_CHECK)
            // if g - g//64 <= gasAmount, revert
            // (we subtract g//64 because of EIP-150)
            if iszero(gt(sub(g, div(g, 64)), gasAmount)) {
                revert(0, 0)
            }
            // solidity calls check that a contract actually exists at the destination, so we do the same
            if iszero(extcodesize(target)) {
                revert(0, 0)
            }
            // call and return whether we succeeded. ignore return data
            // call(gas,addr,value,argsOffset,argsLength,retOffset,retLength)
            success := call(
                gasAmount,
                target,
                0,
                add(data, 0x20),
                mload(data),
                0,
                0
            )
        }
        return success;
    }

    function _getRandomness(
        uint256 requestId,
        uint256 seed,
        RequestCommitment memory rc,
        bytes calldata reqId,
        IMuonClient.SchnorrSign calldata signature
    ) private returns (uint256 randomness) {
        bytes32 commitment = s_requestCommitments[requestId];
        if (commitment == 0) {
            revert NoCorrespondingRequest();
        }

        if (
            commitment !=
            keccak256(
                abi.encode(
                    requestId,
                    rc.blockNum,
                    rc.callbackGasLimit,
                    rc.numWords,
                    rc.sender
                )
            )
        ) {
            revert IncorrectCommitment();
        }

        bytes32 hash = keccak256(
            abi.encodePacked(
                muonAppId,
                reqId,
                block.chainid,
                requestId,
                rc.blockNum,
                rc.callbackGasLimit,
                rc.numWords,
                rc.sender
            )
        );
        console.log(muonAppId);
        console.logBytes(reqId);
        console.log(block.chainid);
        console.log(requestId);
        console.log(rc.blockNum);
        console.log(rc.callbackGasLimit);
        console.log(rc.numWords);
        console.log(rc.sender);
        console.logBytes32(hash);
        verifyMuonSig(reqId, hash, signature);

        randomness = uint256(
            keccak256(abi.encodePacked(seed, blockhash(rc.blockNum)))
        );
    }

    /**
     * @notice Fulfill a randomness request
     * @param requestId corresponding requestId to fulfill
     * @param rc request commitment pre-image, committed to at request time
     * @param reqId Muon reqId
     * @param signature Muon sig
     * @dev simulated offchain to determine gas usage
     */
    function fulfillRandomWords(
        uint256 requestId,
        RequestCommitment memory rc,
        bytes calldata reqId,
        IMuonClient.SchnorrSign calldata signature
    ) external nonReentrant {
        uint256 randomness = _getRandomness(
            requestId,
            signature.signature,
            rc,
            reqId,
            signature
        );

        uint256[] memory randomWords = new uint256[](rc.numWords);
        for (uint256 i = 0; i < rc.numWords; i++) {
            randomWords[i] = uint256(keccak256(abi.encode(randomness, i)));
        }

        delete s_requestCommitments[requestId];
        DeRandConsumerBase v;
        bytes memory resp = abi.encodeWithSelector(
            v.rawFulfillRandomWords.selector,
            requestId,
            randomWords
        );
        // Call with explicitly the amount of callback gas requested
        // Important to not let them exhaust the gas budget and avoid oracle payment.
        // Do not allow any non-view/non-pure coordinator functions to be called
        // during the consumers callback code via reentrancyLock.
        // Note that _callWithExactGas will revert if we do not have sufficient gas
        // to give the callee their requested amount.
        s_config.reentrancyLock = true;
        bool success = _callWithExactGas(rc.callbackGasLimit, rc.sender, resp);
        s_config.reentrancyLock = false;

        // Include payment in the event for tracking costs.
        emit RandomWordsFulfilled(requestId, rc.sender, randomness, success);
    }

    function verifyMuonSig(
        bytes calldata reqId,
        bytes32 hash,
        IMuonClient.SchnorrSign calldata sign
    ) internal {
        bool verified = muon.muonVerify(
            reqId,
            uint256(hash),
            sign,
            muonPublicKey
        );
        require(verified, "Invalid signature!");
    }

    modifier nonReentrant() {
        if (s_config.reentrancyLock) {
            revert Reentrant();
        }
        _;
    }
}
