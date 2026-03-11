// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

abstract contract Pausable {
    // ---- Errors ---- //
    error Pausable__EnforcedPause();
    error Pausable__ExpectedPause();

    // ---- Events ---- //
    event Paused();
    event Unpaused();

    // ---- Storage ---- //
    uint256 private s_paused;

    // ---- Modifiers ---- //
    modifier whenNotPaused() {
        if (s_paused == 1) revert Pausable__EnforcedPause();
        _;
    }

    modifier whenPaused() {
        if (s_paused == 0) revert Pausable__ExpectedPause();
        _;
    }

    // ---- View ---- //
    function paused() public view returns (bool) {
        return s_paused == 1;
    }

    // ---- Internal ---- //
    function _pause() internal whenNotPaused {
        s_paused = 1;
        emit Paused();
    }

    function _unpause() internal whenPaused {
        s_paused = 0;
        emit Unpaused();
    }
}
