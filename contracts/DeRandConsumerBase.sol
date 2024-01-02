// SPDX-License-Identifier: MIT
pragma solidity ^0.8.4;

abstract contract DeRandConsumerBase {
    error OnlyCoordinatorCanFulfill(address have, address want);
    // solhint-disable-next-line chainlink-solidity/prefix-immutable-variables-with-i
    address private immutable coordinator;

    /**
     * @param _coordinator address of coordinator contract
     */
    constructor(address _coordinator) {
        coordinator = _coordinator;
    }

    /**
     * @param requestId The Id initially returned by requestRandomness
     * @param randomWords Random numbers
     */
    // solhint-disable-next-line chainlink-solidity/prefix-internal-functions-with-underscore
    function fulfillRandomWords(
        uint256 requestId,
        uint256[] memory randomWords
    ) internal virtual;

    // rawFulfillRandomness is called by coordinator
    function rawFulfillRandomWords(
        uint256 requestId,
        uint256[] memory randomWords
    ) external {
        if (msg.sender != coordinator) {
            revert OnlyCoordinatorCanFulfill(msg.sender, coordinator);
        }
        fulfillRandomWords(requestId, randomWords);
    }
}
