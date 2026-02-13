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
    uint256 public totalProfilesRegistered;
    uint256 public totalProposalsSent;
    uint256 public totalSparksClaimed;
    uint256 public treasuryBalance;
    uint256 public activeProfileCount;

    struct RomanceProfile {
        address wallet;
        bytes32 profileHash;
        uint8 preferenceFlags;
        uint256 registeredAtBlock;
        bool exists;
    }

    struct ProposalRecord {
        address fromAddr;
        address toAddr;
        uint256 affinityScore;
        uint256 proposedAtBlock;
        bytes32 proposalNonce;
    }

    mapping(address => RomanceProfile) private _profiles;
    mapping(address => uint256) public sparkBalance;
    mapping(address => uint256) private _lastProposalBlock;
    mapping(address => uint256) private _lastSparkClaimBlock;
    mapping(address => uint256) private _sparksClaimedThisEpoch;
    mapping(bytes32 => bool) public proposalNonceUsed;
    mapping(uint256 => bool) private _epochAdvanced;
    address[] private _profileList;
    ProposalRecord[] private _proposalHistory;

    modifier onlyCupid() {
        if (msg.sender != cupidGuardian) revert AffinityErr_NotCupid();
        _;
    }

    modifier whenNotPaused() {
        if (paused()) revert AffinityErr_Paused();
        _;
    }

    modifier onlyEpochAdvancer() {
        if (msg.sender != cupidGuardian && msg.sender != cupidTreasury) revert AffinityErr_NotEpochAdvancer();
        _;
    }

    constructor() {
        cupidGuardian = address(0x5E7a2c9F4b1d8e3A0c6B9f2E5d7a4C1b8e0F3a6);
        cupidTreasury = address(0xA1f4C8b2E9d6F0a3B7c1D5e8f2A4b6C0d9E3a7);
        genesisBlock = block.number;
        affinitySeed = keccak256(abi.encodePacked(block.timestamp, block.prevrandao, block.chainid, "romeo_verona"));
        currentSparkEpoch = 0;
        totalProfilesRegistered = 0;
        totalProposalsSent = 0;
        totalSparksClaimed = 0;
        treasuryBalance = 0;
        activeProfileCount = 0;
    }

    function registerProfile(bytes32 profileHash, uint8 preferenceFlags) external whenNotPaused nonReentrant {
        if (profileHash == bytes32(0)) revert AffinityErr_ZeroProfileHash();
        if (preferenceFlags >= (1 << PREFERENCE_FLAG_COUNT)) revert AffinityErr_InvalidPreferenceFlag();
        RomanceProfile storage p = _profiles[msg.sender];
        if (p.exists) revert AffinityErr_ProfileAlreadyExists();
        if (activeProfileCount >= MAX_REGISTERED_PROFILES) revert AffinityErr_MaxProfilesReached();

        p.wallet = msg.sender;
        p.profileHash = profileHash;
        p.preferenceFlags = preferenceFlags;
        p.registeredAtBlock = block.number;
        p.exists = true;
        _profileList.push(msg.sender);
        activeProfileCount++;
        totalProfilesRegistered++;
        emit ProfileRegistered(msg.sender, profileHash, preferenceFlags, block.number);
    }

    function updateProfile(bytes32 newProfileHash) external whenNotPaused {
        if (newProfileHash == bytes32(0)) revert AffinityErr_ZeroProfileHash();
        RomanceProfile storage p = _profiles[msg.sender];
        if (!p.exists) revert AffinityErr_ProfileMissing();
        p.profileHash = newProfileHash;
        emit ProfileUpdated(msg.sender, newProfileHash, block.number);
    }

    function _computeAffinity(address seeker, address target) internal view returns (uint256) {
        RomanceProfile storage sp = _profiles[seeker];
        RomanceProfile storage tp = _profiles[target];
        if (!sp.exists || !tp.exists) return 0;
        uint256 xorFlags = uint256(sp.preferenceFlags ^ tp.preferenceFlags);
        uint256 matchBits = 0;
        for (uint256 i = 0; i < PREFERENCE_FLAG_COUNT; i++) {
            if ((xorFlags & (1 << i)) == 0) matchBits++;
        }
        uint256 base = (matchBits * AFFINITY_SCALE) / PREFERENCE_FLAG_COUNT;
        uint256 mix = uint256(keccak256(abi.encodePacked(affinitySeed, seeker, target, block.number - genesisBlock))) % 200001;
        uint256 bonus = (mix * AFFINITY_SCALE) / 200000;
        uint256 score = base + (bonus % (AFFINITY_SCALE - base + 1));
        if (score > AFFINITY_SCALE) score = AFFINITY_SCALE;
        return score;
    }

    function proposeSoulmate(address toAddr, bytes32 proposalNonce) external whenNotPaused nonReentrant returns (uint256 affinityScore) {
        if (toAddr == address(0)) revert AffinityErr_ZeroAddress();
        if (toAddr == msg.sender) revert AffinityErr_SelfProposal();
        if (proposalNonce == bytes32(0) || proposalNonceUsed[proposalNonce]) revert AffinityErr_InvalidProposalNonce();
        if (block.number < _lastProposalBlock[msg.sender] + PROPOSAL_COOLDOWN_BLOCKS) revert AffinityErr_ProposalCooldown();

        RomanceProfile storage fromProfile = _profiles[msg.sender];
        RomanceProfile storage toProfile = _profiles[toAddr];
        if (!fromProfile.exists) revert AffinityErr_ProfileMissing();
        if (!toProfile.exists) revert AffinityErr_ProfileMissing();

        affinityScore = _computeAffinity(msg.sender, toAddr);
        proposalNonceUsed[proposalNonce] = true;
        _lastProposalBlock[msg.sender] = block.number;
        totalProposalsSent++;

        _proposalHistory.push(ProposalRecord({
            fromAddr: msg.sender,
            toAddr: toAddr,
            affinityScore: affinityScore,
            proposedAtBlock: block.number,
            proposalNonce: proposalNonce
        }));

        emit SoulmateProposed(msg.sender, toAddr, affinityScore, block.number, proposalNonce);
        emit CompatibilityRevealed(msg.sender, toAddr, affinityScore, block.number);
        return affinityScore;
    }

    function proposeSoulmateBatch(
        address[] calldata targets,
        bytes32[] calldata nonces
    ) external whenNotPaused nonReentrant {
        uint256 n = targets.length;
        if (n == 0 || n > BATCH_PROPOSE_LIMIT) revert AffinityErr_CapReached();
        if (nonces.length != n) revert AffinityErr_InvalidProposalNonce();
        if (block.number < _lastProposalBlock[msg.sender] + PROPOSAL_COOLDOWN_BLOCKS) revert AffinityErr_ProposalCooldown();

        RomanceProfile storage fromProfile = _profiles[msg.sender];
        if (!fromProfile.exists) revert AffinityErr_ProfileMissing();

        for (uint256 i = 0; i < n; i++) {
            address toAddr = targets[i];
            bytes32 nonce = nonces[i];
            if (toAddr == address(0) || toAddr == msg.sender) continue;
            if (nonce == bytes32(0) || proposalNonceUsed[nonce]) continue;
            if (!_profiles[toAddr].exists) continue;

            uint256 score = _computeAffinity(msg.sender, toAddr);
            proposalNonceUsed[nonce] = true;
            _proposalHistory.push(ProposalRecord({
                fromAddr: msg.sender,
                toAddr: toAddr,
                affinityScore: score,
                proposedAtBlock: block.number,
                proposalNonce: nonce
            }));
            emit SoulmateProposed(msg.sender, toAddr, score, block.number, nonce);
            emit CompatibilityRevealed(msg.sender, toAddr, score, block.number);
        }
        _lastProposalBlock[msg.sender] = block.number;
        totalProposalsSent += n;
    }

    function claimSparksAfterProposal() external whenNotPaused nonReentrant {
        _advanceSparkEpochIfNeeded();
        uint256 claim = SPARK_CLAIM_PER_MATCH;
        uint256 already = _sparksClaimedThisEpoch[msg.sender];
        if (already + claim > MAX_SPARK_CLAIM_PER_EPOCH) {
            claim = already >= MAX_SPARK_CLAIM_PER_EPOCH ? 0 : MAX_SPARK_CLAIM_PER_EPOCH - already;
        }
        if (block.number < _lastSparkClaimBlock[msg.sender] + SPARK_CLAIM_COOLDOWN_BLOCKS && already > 0) {
            claim = 0;
        }
        if (claim > 0) {
            sparkBalance[msg.sender] += claim;
            totalSparksClaimed += claim;
            _sparksClaimedThisEpoch[msg.sender] += claim;
            _lastSparkClaimBlock[msg.sender] = block.number;
            emit SparkIgnited(msg.sender, claim, currentSparkEpoch, block.number);
        }
