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
    event SparkIgnited(
        address indexed recipient,
        uint256 amount,
        uint256 epochIndex,
        uint256 ignitedAtBlock
    );
    event CompatibilityRevealed(
        address indexed seeker,
        address indexed target,
        uint256 score,
        uint256 revealedAtBlock
    );
    event ProfileRegistered(
        address indexed user,
        bytes32 profileHash,
        uint8 preferenceFlags,
        uint256 registeredAtBlock
    );
    event ProfileUpdated(
        address indexed user,
        bytes32 newProfileHash,
        uint256 updatedAtBlock
    );
    event MutualSpark(
        address indexed partyA,
        address indexed partyB,
        uint256 combinedSparks,
        uint256 atBlock
    );
    event EpochAdvanced(uint256 previousEpoch, uint256 newEpoch, uint256 atBlock);
    event CupidTreasuryTopped(uint256 amount, address indexed fromAddr, uint256 newBalance);
    event GuardianPauseToggled(bool paused);

    error AffinityErr_ZeroAddress();
    error AffinityErr_ProfileAlreadyExists();
    error AffinityErr_ProfileMissing();
    error AffinityErr_SelfProposal();
    error AffinityErr_CooldownActive();
    error AffinityErr_CapReached();
    error AffinityErr_NotCupid();
    error AffinityErr_Paused();
    error AffinityErr_InvalidProposalNonce();
    error AffinityErr_ProposalCooldown();
    error AffinityErr_SparkEpochWindow();
    error AffinityErr_ClaimCapThisEpoch();
    error AffinityErr_InvalidPreferenceFlag();
    error AffinityErr_MaxProfilesReached();
    error AffinityErr_ZeroProfileHash();
    error AffinityErr_WithdrawFailed();
    error AffinityErr_NotEpochAdvancer();

    uint256 public constant AFFINITY_SCALE = 1_000_000;
    uint256 public constant MAX_REGISTERED_PROFILES = 2048;
    uint256 public constant PROPOSAL_COOLDOWN_BLOCKS = 144;
    uint256 public constant SPARK_CLAIM_PER_MATCH = 88;
    uint256 public constant MAX_SPARK_CLAIM_PER_EPOCH = 880;
    uint256 public constant SPARK_EPOCH_BLOCKS = 512;
    uint256 public constant SPARK_CLAIM_COOLDOWN_BLOCKS = 64;
    uint256 public constant PREFERENCE_FLAG_COUNT = 8;
    uint256 public constant BATCH_PROPOSE_LIMIT = 24;
    bytes32 public constant SOULMATE_DOMAIN =
        bytes32(uint256(0x9e8d7c6b5a493827160e5d4c3b2a1908f7e6d5c4b3a2918));

    address public immutable cupidGuardian;
    address public immutable cupidTreasury;
    uint256 public immutable genesisBlock;
    bytes32 public immutable affinitySeed;

    uint256 public currentSparkEpoch;
