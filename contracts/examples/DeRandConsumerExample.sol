// SPDX-License-Identifier: MIT
pragma solidity ^0.8.7;

import "@chainlink/contracts/src/v0.8/interfaces/VRFCoordinatorV2Interface.sol";
import "@chainlink/contracts/src/v0.8/vrf/VRFConsumerBaseV2.sol";

contract DeRandConsumerExample is VRFConsumerBaseV2{
    event RequestSent(uint256 requestId, uint32 numWords);
    event RequestFulfilled(uint256 requestId, uint256[] randomWords);

    struct RequestStatus {
        bool fulfilled;
        bool exists;
        uint256[] randomWords;
    }
    mapping(uint256 => RequestStatus)
        public s_requests; /* requestId --> requestStatus */
    VRFCoordinatorV2Interface COORDINATOR;

    // past requests Id.
    uint256[] public requestIds;
    uint256 public lastRequestId;

    // The gas lane to use, which specifies the maximum gas price to bump to.
    // For a list of available gas lanes on each network,
    // see https://docs.chain.link/docs/vrf/v2/subscription/supported-networks/#configurations
    bytes32 keyHash =
        0x474e34a077df58807dbe9c96d3c009b23b3c6d0cce433e59bbf5b34f823bc56c;

    uint32 callbackGasLimit = 100000;
    uint16 requestConfirmations = 3;

    uint32 numWords = 2;

    /**
    * DeRand protocol is compatible with Chainlink VRF
    * Consumer contracts.
    * The only difference is the Coordinator address, 
    * which is specific to each network.
    *
    * DeRand's Coordinator address on Mumbai testnet:
    * 0x54213dd1052A7c1B2e8a856234227f033Aff3D8b
    */
    constructor()
        VRFConsumerBaseV2(0x54213dd1052A7c1B2e8a856234227f033Aff3D8b)
    {
        COORDINATOR = VRFCoordinatorV2Interface(
            0x54213dd1052A7c1B2e8a856234227f033Aff3D8b
        );
    }

    /**
     * Requests random numbers
     */
    function requestRandomWords()
        external
        returns (uint256 requestId)
    {
        requestId = COORDINATOR.requestRandomWords(
            keyHash,
            // subscriptionId is not important for DeRand protocol.
            // We will keep it to maintain compatibility with Chainlink VRF
            0, // s_subscriptionId
            requestConfirmations,
            callbackGasLimit,
            numWords
        );
        s_requests[requestId] = RequestStatus({
            randomWords: new uint256[](0),
            exists: true,
            fulfilled: false
        });
        requestIds.push(requestId);
        lastRequestId = requestId;
        emit RequestSent(requestId, numWords);
        return requestId;
    }

    /**
     * This function will be called by DeRand Executors
     * to fullfill the random numbers.
     */
    function fulfillRandomWords(
        uint256 _requestId,
        uint256[] memory _randomWords
    ) internal override {
        require(s_requests[_requestId].exists, "request not found");
        s_requests[_requestId].fulfilled = true;
        s_requests[_requestId].randomWords = _randomWords;
        emit RequestFulfilled(_requestId, _randomWords);
    }

    function getRequestStatus(
        uint256 _requestId
    ) external view returns (bool fulfilled, uint256[] memory randomWords) {
        require(s_requests[_requestId].exists, "request not found");
        RequestStatus memory request = s_requests[_requestId];
        return (request.fulfilled, request.randomWords);
    }
}
