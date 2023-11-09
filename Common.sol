// SPDX-License-Identifier: MIT
pragma solidity 0.8.20;

import "@openzeppelin/contracts/utils/structs/EnumerableSet.sol";
import "@openzeppelin/contracts/utils/structs/EnumerableMap.sol";

contract CommonStructs {
    using EnumerableSet for EnumerableSet.AddressSet;
    using EnumerableSet for EnumerableSet.Bytes32Set;

    /**
     * @notice Defines the structure of an organization.
    */
    struct Org {
        string name;  // Name of the organization.
        address founder;  // Address of the organization's founder.
        uint256 memberLimit;  // Maximum number of members allowed in the organization.
        uint256 memberCount;  // Current count of members in the organization.
        EnumerableSet.AddressSet members;  // Set of member addresses.
        ExtensionProposal[] proposals;  // Array of member limit extension proposals.
        mapping(address => OfficialNomination) officialNominations;  // Mapping of addresses to their respective official nomination details.
        mapping(bytes32 => LawProposal) lawProposals;  // Mapping of law proposal IDs to their respective details.
        mapping(bytes32 => LawProposal) enactedLaws;  // Mapping of enacted law IDs to their respective details.
        EnumerableSet.Bytes32Set lawProposalIds;  // Set of IDs for all law proposals.
        EnumerableSet.Bytes32Set laws;  // Set of IDs for all enacted laws.
        mapping(address => OfficialRemovalProposal) removalProposals;  // Mapping of official addresses to their respective removal proposal details.
        mapping(address => bool) isOfficial;  // Mapping to check if a given address is an official.
        mapping(address => uint256) officialRemovalProposalIds;  // Mapping of official addresses to their respective removal proposal IDs.
    }

    /**
    * @notice Defines the structure of a capacity extension proposal.
    */
    struct ExtensionProposal {
        uint256 newLimit;  // Proposed new member limit.
        uint256 voteCount;  // Number of votes supporting the proposal.
        uint256 againstVoteCount;  // Number of votes opposing the proposal.
        mapping(address => bool) hasVoted;  // Mapping to keep track of members who have already voted.
        bool executed;  // Indicates if the proposal has been executed or not.
        uint256 endTimestamp;  // Timestamp marking the end of the voting period.
    }

    struct OfficialNomination {
        address nominee;  // Address of the nominated official.
        uint256 votes;  // Number of votes received by the nominee.
        mapping(address => bool) voters;  // Mapping to keep track of members who have voted for the nominee.
        bool isElected;  // Indicates if the nominee was elected as an official.
        uint256 tenureEndTime;  // Timestamp marking the end of the official's tenure.
        bool isActive;  // Indicates if the official is currently active.
    }

    struct LawProposal {
        address proposer;  // Address of the member proposing the law.
        string description;  // Description of the proposed law.
        uint256 votesInFavor;  // Number of votes supporting the proposed law.
        uint256 votesAgainst;  // Number of votes opposing the proposed law.
        mapping(address => bool) hasVoted;  // Mapping to keep track of members who have voted on the law proposal.
        bool isEnacted;  // Indicates if the law proposal has been enacted.
        uint256 requiredApprovalPercentage;  // Percentage of votes required to enact the law.
        uint256 endTimestamp;  // Timestamp marking the end of the voting period for the law.
    }

    struct OfficialRemovalProposal {
        address targetOfficial;  // Address of the official proposed for removal.
        uint256 votesInFavor;  // Number of votes supporting the removal.
        uint256 votesAgainst;  // Number of votes opposing the removal.
        mapping(address => bool) hasVoted;  // Mapping to keep track of members who have voted on the removal proposal.
        bool isExecuted;  // Indicates if the removal has been executed.
        uint256 endTimestamp;  // Timestamp marking the end of the voting period for the removal.
    }
}

library Errors {
    // User Verification and Membership Errors
    error NotVerified(address _callerAddress);  // Error thrown when a caller is not verified.
    error AlreadyJoined(address _callerAddress, uint256 _orgId);  // Error thrown when a caller has already joined the specified organization.
    error NotAMemberOfOrg(address _callerAddress, uint256 _orgId);  // Error thrown when a caller is not a member of the specified organization.

    // Organization Capacity Errors
    error OrganizationFull(uint256 _orgId);  // Error thrown when an organization has reached its member limit.

    // Proposal Specific Errors
    error PreviousProposalStillActive(uint256 _orgId);  // Error thrown when an older proposal is still active.
    error NoActiveProposals(uint256 _orgId);  // Error thrown when there are no active proposals for an organization.
    error AlreadyVoted(address _callerAddress, uint256 _proposalIndex);  // Error thrown when a member has already voted on a proposal.
    error ProposalAlreadyExecuted(uint256 _proposalIndex);  // Error thrown when trying to interact with a proposal that's already been executed.
    error VotingPeriodEnded(uint256 _proposalIndex);  // Error thrown when trying to vote after the voting period has ended.

    // General Errors
    error InvalidOrganizationId(uint256 _orgId);  // Error thrown when an invalid organization ID is used.
    error InvalidProposalIndex(uint256 _orgId, uint256 _proposalIndex);  // Error thrown when an invalid proposal index is used for a given organization.
    error NoProposalsForOrg(uint256 _orgId);  // Error thrown when there are no proposals associated with a given organization.
}

library Events {
    // Organization Events
    event OrganizationCreated(uint256 indexed _orgId, address indexed _creatorAddress, string _orgName);  // Emitted when a new organization is created.
    event MemberJoined(uint256 _orgId, address _address);  // Emitted when a new member joins an organization.
    event MemberLeft(uint256 _orgId, address _address);  // Emitted when a member leaves an organization.

    // Voting and Proposal Events
    event NewProposal(uint256 _orgId, uint256 _newLimit);  // Emitted when a new member limit extension proposal is created.
    event Voted(uint256 _orgId, address _address, bool _vote);  // Emitted when a member votes on a proposal.

    // Official Nomination Events
    event OfficialProposed(uint256 _orgId, address _nomineeAddress);  // Emitted when a new official nomination is proposed.
    event OfficialNominated(uint256 indexed _orgId, address indexed _nominee);  // Emitted when an official is nominated.
    event OfficialVoted(uint256 indexed _orgId, address indexed _nominee, address _voterAddress);  // Emitted when a member votes on an official nomination.
    event OfficialElected(uint256 indexed _orgId, address indexed _nomineeAddress);  // Emitted when an official is elected.

    // Law Proposal Events
    event LawProposed(uint256 _orgId, string description);  // Emitted when a new law is proposed.
    event LawVotedOn(uint256 _orgId, bytes32 _lawIdentifier, bool _vote);  // Emitted when a member votes on a law proposal.
    event LawPassed(uint256 _orgId, bytes32 _lawIdentifier);  // Emitted when a law proposal is enacted.
    event LawRejected(uint256 _orgId, bytes32 _lawIndex);  // Emitted when a law proposal is rejected.

    // Official Removal Events
    event RemovalProposed(uint256 _orgId, address _officialAddress);  // Emitted when an official removal proposal is created.
    event RemovalVotedOn(uint256 _orgId, address _officialAddress, bool _vote);  // Emitted when a member votes on an official removal proposal.
    event OfficialRemoved(uint256 _orgId, address _officialAddress);  // Emitted when an official is removed.
}
