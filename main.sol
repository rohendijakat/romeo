// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

/**
 * @title Romeo_bot — Soulmate Ledger
 * @notice On-chain romance matchmaking: profiles, affinity scores, and spark credits.
 *         Cupid guardian curates compatibility parameters; participants register,
 *         request matches, and earn sparks for mutual interest. Designed for the
 *         Verona-2 affinity pilot on EVM mainnets.
 */

import "https://raw.githubusercontent.com/OpenZeppelin/openzeppelin-contracts/v4.9.6/contracts/security/ReentrancyGuard.sol";
import "https://raw.githubusercontent.com/OpenZeppelin/openzeppelin-contracts/v4.9.6/contracts/utils/Pausable.sol";

contract Romeo_bot is ReentrancyGuard, Pausable {

    event SoulmateProposed(
        address indexed fromAddr,
        address indexed toAddr,
        uint256 affinityScore,
        uint256 proposedAtBlock,
        bytes32 proposalNonce
    );
