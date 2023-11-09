// SPDX-License-Identifier: MIT
pragma solidity 0.8.20;

import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/utils/structs/EnumerableSet.sol";
import "./Common.sol";
import "./Verifier.sol";

/**
 * @title AnarchyDAO
 * @dev A contract that allows for the creation and management of decentralized organizations.
 * Users must possess a verified badge (an NFT from the Verifier contract) in order to join an organization.
 * Members can join and leave organizations, and the organization members can propose and vote on extending the capacity.
 */
contract AnarchyDAO is Ownable {
    using EnumerableSet for EnumerableSet.AddressSet;
    using EnumerableSet for EnumerableSet.Bytes32Set;

    /// @notice The Verifier contract to check if an address owns a VerifiedBadge NFT.
    Verifier private _verifiedBadge;

    // Mapping to track if an organization name is already taken
    mapping(string => bool) private orgNameExists;

    /// @notice Mapping from organization ID to its data.
    mapping(uint256 => CommonStructs.Org) private organizations;

    /// @notice Total number of organizations created.
    uint256 public orgCount = 0;

    /// @notice Mapping of a user address to and organization ID.
    mapping(address => mapping(uint256 => bool)) public memberToOrgId;

    /**
     * @notice Initializes the `Organization` contract.
     * @param verifiedBadgeAddress Address of the deployed Verifier contract.
     */
    constructor(address verifiedBadgeAddress) Ownable(msg.sender) {
        _verifiedBadge = Verifier(verifiedBadgeAddress);
    }

    /**
    * @notice Creates a new organization with a unique name.
    * @param _memberLimit Initial member limit of the organization.
    * @param _orgName Name of the organization.
    * @return The ID of the newly created organization.
    */
    function createOrganization(uint256 _memberLimit, string memory _orgName) external returns (uint256) {
        require(_verifiedBadge.balanceOf(msg.sender) > 0, "User must be verified to create an organization");
        require(!orgNameExists[_orgName], "Organization name already taken");

        orgCount++;  // Increment the orgCount which will act as the new organization's ID.

        CommonStructs.Org storage newOrg = organizations[orgCount];
        newOrg.memberLimit = _memberLimit;
        newOrg.memberCount = 1;
        newOrg.name = _orgName;
        newOrg.members.add(msg.sender); // Add the creator to the organization's members
        orgNameExists[_orgName] = true; // Mark the organization name as taken

        memberToOrgId[msg.sender][orgCount] = true; // Update the mapping

        emit Events.OrganizationCreated(orgCount, msg.sender, _orgName);

        return orgCount; // Return the new organization's ID.
    }

    /**
     * @notice Allows a user to join an organization.
     * @param _orgId The ID of the organization to join.
     */
    function joinOrganization(uint256 _orgId) external {
        if (_verifiedBadge.balanceOf(msg.sender) <= 0) {
            revert Errors.NotVerified(msg.sender);
        }

        if (organizations[_orgId].members.length() >= organizations[_orgId].memberLimit) {
            revert Errors.OrganizationFull(_orgId);
        }

        if (organizations[_orgId].members.contains(msg.sender)) {
            revert Errors.AlreadyJoined(msg.sender, _orgId);
        }

        organizations[_orgId].members.add(msg.sender);
        organizations[_orgId].memberCount++;
        memberToOrgId[msg.sender][_orgId] = true;

        emit Events.MemberJoined(_orgId, msg.sender);
    }

    /**
     * @notice Allows a member to leave an organization.
     * @param _orgId ID of the organization to leave.
     */
    function leaveOrganization(uint256 _orgId) external {
        if (!organizations[_orgId].members.contains(msg.sender)) {
            revert Errors.NotAMemberOfOrg(msg.sender, _orgId);
        }

        organizations[_orgId].members.remove(msg.sender);
        organizations[_orgId].memberCount--;
        memberToOrgId[msg.sender][_orgId] = false;

        emit Events.MemberLeft(_orgId, msg.sender);
    }

    /**
     * @notice Checks if a specific address is a member of a given organization.
     * @param _orgId ID of the organization.
     * @param _memberAddress Address to verify.
     * @return True if the address is a member, false otherwise.
     */
    function isMemberOfOrganization(uint256 _orgId, address _memberAddress) public view returns (bool) {
        return organizations[_orgId].members.contains(_memberAddress);
    }

    /**
    * @notice Creates a proposal for extending the member limit of an organization.
    * @param _orgId ID of the organization.
    * @param _newLimit Proposed new member limit.
    * @param _numberOfDays Proposed number of days for the proposal to be actibe.
    */
    function createExtensionProposal(uint256 _orgId, uint256 _newLimit, uint _numberOfDays) external {
        if (!isMemberOfOrganization(_orgId, msg.sender)) {
            revert Errors.NotAMemberOfOrg(msg.sender, _orgId);
        }

        CommonStructs.ExtensionProposal[] storage orgProposals = organizations[_orgId].proposals;

        if (orgProposals.length > 0) {
            CommonStructs.ExtensionProposal storage lastProposal = orgProposals[orgProposals.length - 1];

            if (!lastProposal.executed && block.timestamp <= lastProposal.endTimestamp) {
                revert Errors.PreviousProposalStillActive(_orgId);
            }
        }

        CommonStructs.ExtensionProposal storage newProposal = orgProposals.push();
        newProposal.newLimit = _newLimit;
        newProposal.voteCount = 0;
        newProposal.againstVoteCount = 0;
        newProposal.executed = false;
        newProposal.endTimestamp = block.timestamp + _numberOfDays * 1 days;

        emit Events.NewProposal(_orgId, _newLimit);
    }

    /**
    * @notice Vote on a proposal to extend the member limit of an organization.
    * @param _orgId ID of the organization.
    * @param _inFavor True if voting in favor, false if against.
    */
    function voteOnExtensionProposal(uint256 _orgId, bool _inFavor) external {
        // Checks to validate the custom errors
        if (!isMemberOfOrganization(_orgId, msg.sender)) {
            revert Errors.NotAMemberOfOrg(msg.sender, _orgId);
        }

        CommonStructs.ExtensionProposal[] storage orgProposals = organizations[_orgId].proposals;

        if (orgProposals.length == 0) {
            revert Errors.NoActiveProposals(_orgId);
        }

        CommonStructs.ExtensionProposal storage currentProposal = orgProposals[orgProposals.length - 1];

        if (currentProposal.hasVoted[msg.sender]) {
            revert Errors.AlreadyVoted(msg.sender, orgProposals.length - 1);
        }

        if (block.timestamp > currentProposal.endTimestamp) {
            revert Errors.VotingPeriodEnded(orgProposals.length - 1);
        }

        if (_inFavor) {
            currentProposal.voteCount++;
        } else {
            currentProposal.againstVoteCount++;
        }

        currentProposal.hasVoted[msg.sender] = true;

        emit Events.Voted(_orgId, msg.sender, _inFavor);
    }

    /**
    * @notice Propose a new official nominee for the organization.
    * @param _orgId The ID of the organization to which the official is being proposed.
    * @param _nominee The Ethereum address of the nominee being proposed as an official.
    */
    function proposeOfficial(uint256 _orgId, address _nominee) external {
        CommonStructs.Org storage org = organizations[_orgId];

        require(isMemberOfOrganization(_orgId, msg.sender), "Not a member");
        require(org.memberCount >= 3, "Organization must have at least 3 members to propose officials");
        require(isMemberOfOrganization(_orgId, _nominee), "Nominee must be a member of the organization");
        require(!org.officialNominations[_nominee].isActive, "Nomination is already active");
        require(!org.isOfficial[_nominee], "Nominee is already an official");

        // Instead of initializing the entire struct at once, initialize each field individually
        org.officialNominations[_nominee].nominee = _nominee;
        org.officialNominations[_nominee].isActive = true;
        org.officialNominations[_nominee].isElected = false;
        org.officialNominations[_nominee].tenureEndTime = 2 * 333 days;

        emit Events.OfficialProposed(_orgId, _nominee);
    }

    /**
     * @notice Allows a member of the organization to vote for a nominee to be an official.
     * @param _orgId The ID of the organization.
     * @param _nominee The address of the nominee.
     */
    function voteForOfficial(uint256 _orgId, address _nominee) external {
        CommonStructs.Org storage org = organizations[_orgId];

        require(isMemberOfOrganization(_orgId, msg.sender), "Not a member");
        require(org.officialNominations[_nominee].isActive, "Nomination is not active or nominee not found");
        require(!org.officialNominations[_nominee].voters[msg.sender], "Member has already voted for this nominee");

        CommonStructs.OfficialNomination storage nomination = org.officialNominations[_nominee];
        nomination.votes++;
        nomination.voters[msg.sender] = true;

        // Check if votes exceed 60% for automatic enactment.
        if (nomination.votes > (org.memberCount * 60) / 100) {
            _enactOfficial(_orgId, _nominee);
        }

        emit Events.OfficialVoted(_orgId, _nominee, msg.sender);
    }

    /**
     * @notice Internal function to enact an official after meeting the voting threshold.
     * @param _orgId The ID of the organization.
     * @param nominee The address of the nominee.
     */
    function _enactOfficial(uint256 _orgId, address nominee) private {
        CommonStructs.Org storage org = organizations[_orgId];

        require(org.officialNominations[nominee].isActive, "Nomination is not active or nominee not found");
        require(!org.officialNominations[nominee].isElected, "Nominee is already an elected official");

        CommonStructs.OfficialNomination storage nomination = org.officialNominations[nominee];
        org.isOfficial[nominee] = true;
        nomination.isElected = true;
        nomination.isActive = false; // Close the vote
        nomination.tenureEndTime = block.timestamp + 256 days;

        emit Events.OfficialElected(_orgId, nominee);
    }

    /**
    * @notice Propose a new law for an organization.
    * @param _orgId The ID of the organization.
    * @param description A description of the proposed law.
    * @param requiredApprovalPercentage The required approval percentage for the law to be enacted.
    * @param durationInDays Time (in days) before the law proposal voting closes.
    */
    function proposeLaw(
        uint256 _orgId,
        string memory description,
        uint8 requiredApprovalPercentage,
        uint256 durationInDays
    ) external {
        CommonStructs.Org storage org = organizations[_orgId];
        require(org.isOfficial[msg.sender], "Not an official");
        require(requiredApprovalPercentage > 0 && requiredApprovalPercentage <= 100, "Invalid approval percentage");

        bytes32 lawId = keccak256(abi.encodePacked(description, block.timestamp, msg.sender));
        require(!org.lawProposalIds.contains(lawId), "Law proposal already exists");

        CommonStructs.LawProposal storage law = org.lawProposals[lawId];
        org.lawProposalIds.add(lawId);

        law.proposer = msg.sender;
        law.description = description;
        law.requiredApprovalPercentage = requiredApprovalPercentage;
        // Convert duration from days to seconds
        law.endTimestamp = block.timestamp + (durationInDays * 1 days);

        emit Events.LawProposed(_orgId, description);
    }

    /**
    * @notice Vote on a proposed law for an organization.
    * @param _orgId The ID of the organization.
    * @param _lawId The unique identifier of the law proposal.
    * @param _inFavor Whether the vote is in favor or against the proposal.
    */
    function voteOnLaw(uint256 _orgId, bytes32 _lawId, bool _inFavor) external {
        CommonStructs.Org storage org = organizations[_orgId];
        require(isMemberOfOrganization(_orgId, msg.sender), "Not a member");
        require(org.lawProposalIds.contains(_lawId), "Law proposal does not exist");
        require(block.timestamp <= org.lawProposals[_lawId].endTimestamp, "Voting period has ended");
        require(!org.lawProposals[_lawId].hasVoted[msg.sender], "Already voted");

        CommonStructs.LawProposal storage law = org.lawProposals[_lawId];

        if (_inFavor) {
            law.votesInFavor++;
        } else {
            law.votesAgainst++;
        }

        law.hasVoted[msg.sender] = true;

        // If voting period has not ended, check if the law has achieved required votes
        if (block.timestamp <= law.endTimestamp) {
            if (law.votesInFavor >= (org.memberCount * law.requiredApprovalPercentage) / 100) {
                // The law has passed, mark it as enacted
                law.isEnacted = true;

                // Add to current enacted laws
                org.laws.add(_lawId);
                org.enactedLaws[_lawId].proposer = law.proposer;
                org.enactedLaws[_lawId].description = law.description;
                org.enactedLaws[_lawId].votesInFavor = law.votesInFavor;
                org.enactedLaws[_lawId].votesAgainst = law.votesAgainst;
                org.enactedLaws[_lawId].isEnacted = law.isEnacted;
                org.enactedLaws[_lawId].requiredApprovalPercentage = law.requiredApprovalPercentage;
                org.enactedLaws[_lawId].endTimestamp = block.timestamp;

                // Remove the law ID from the proposals set
                org.lawProposalIds.remove(_lawId);

                emit Events.LawPassed(_orgId, _lawId);

                // Since the law has passed, we can safely delete the proposal
                delete org.lawProposals[_lawId];
            }
        } else {
            // Voting period ended without passing the law, so it's rejected
            emit Events.LawRejected(_orgId, _lawId);

            // Remove the law ID from the proposals set since it's no longer active
            org.lawProposalIds.remove(_lawId);

            // Since the law is rejected, we can safely delete the proposal
            delete org.lawProposals[_lawId];
        }
    }

    /**
    * @notice Fetches the description of an enacted law for a given organization.
    * @param _orgId The ID of the organization.
    * @param _lawId The unique identifier of the enacted law.
    * @return description Returns the description of the specified enacted law.
    */
    function getLaw(uint256 _orgId, bytes32 _lawId) public view returns (string memory description) {
        CommonStructs.Org storage org = organizations[_orgId];
        CommonStructs.LawProposal storage law = org.enactedLaws[_lawId];

        return law.description;
    }

    /**
    * @notice Fetches all proposed laws and their descriptions for a given organization.
    * @param _orgId The ID of the organization.
    * @return ids An array of unique identifiers for each proposed law.
    * @return descriptions An array of descriptions corresponding to each proposed law.
    */
    function getAllProposedLaws(uint256 _orgId) public view returns (bytes32[] memory ids, string[] memory descriptions) {
        CommonStructs.Org storage org = organizations[_orgId];

        uint256 proposalCount = org.lawProposalIds.length();
        bytes32[] memory idsTemp = new bytes32[](proposalCount);
        string[] memory descriptionsTemp = new string[](proposalCount);

        for (uint i = 0; i < proposalCount; i++) {
            bytes32 lawId = org.lawProposalIds.at(i);
            CommonStructs.LawProposal storage proposal = org.lawProposals[lawId];
            idsTemp[i] = lawId;
            descriptionsTemp[i] = proposal.description;
        }

        return (idsTemp, descriptionsTemp);
    }

    /**
    * @notice Fetches all enacted laws and their descriptions for a given organization.
    * @param _orgId The ID of the organization.
    * @return ids An array of unique identifiers for each enacted law.
    * @return descriptions An array of descriptions corresponding to each enacted law.
    */
    function getAllEnactedLaws(uint256 _orgId) public view returns (bytes32[] memory ids, string[] memory descriptions) {
        CommonStructs.Org storage org = organizations[_orgId];

        bytes32[] memory idsTemp = new bytes32[](org.laws.length());
        string[] memory descriptionsTemp = new string[](org.laws.length());

        for (uint i = 0; i < org.laws.length(); i++) {
            bytes32 lawId = org.laws.at(i);
            idsTemp[i] = lawId;
            descriptionsTemp[i] = org.enactedLaws[lawId].description;
        }

        return (idsTemp, descriptionsTemp);
    }

    /**
    * @notice Propose the removal of an official in an organization.
    * @param _orgId The ID of the organization.
    * @param _officialAddress The address of the official being proposed for removal.
    */
    function proposeRemovalOfOfficial(uint256 _orgId, address _officialAddress) external {
        CommonStructs.Org storage org = organizations[_orgId];

        require(isMemberOfOrganization(_orgId, msg.sender), "Not a member");
        require(org.isOfficial[_officialAddress], "Target is not an official");
        require(org.officialRemovalProposalIds[_officialAddress] == 0, "Removal proposal already exists for this official");

        CommonStructs.OfficialRemovalProposal storage removal = org.removalProposals[_officialAddress];
        org.officialRemovalProposalIds[_officialAddress] = _orgId;

        removal.targetOfficial = _officialAddress;
        removal.endTimestamp = block.timestamp + 7 days;

        emit Events.RemovalProposed(_orgId, _officialAddress);
    }

    /**
    * @notice Vote on a proposal to remove an official in an organization.
    * @param _orgId The ID of the organization.
    * @param _officialAddress The address of the official being proposed for removal.
    * @param _inFavor Whether the vote is in favor or against the removal.
    */
    function voteOnRemoval(uint256 _orgId, address _officialAddress, bool _inFavor) external {
        CommonStructs.Org storage org = organizations[_orgId];

        require(isMemberOfOrganization(_orgId, msg.sender), "Not a member");

        CommonStructs.OfficialRemovalProposal storage removal = org.removalProposals[_officialAddress];
        require(removal.endTimestamp != 0, "Removal proposal not found");

        if (block.timestamp >= removal.endTimestamp) {
            delete org.removalProposals[_officialAddress];
            delete org.officialRemovalProposalIds[_officialAddress];
        }

        require(!removal.hasVoted[msg.sender], "Already voted");

        if (_inFavor) {
            removal.votesInFavor++;
        } else {
            removal.votesAgainst++;
        }

        removal.hasVoted[msg.sender] = true;

        // Check if votes in favor surpass 80% of the total organization members
        if (removal.votesInFavor >= (org.memberCount * 80) / 100) {
            // Remove the official and delete the removal proposal
            org.isOfficial[_officialAddress] = false;
            delete org.removalProposals[_officialAddress];
            delete org.officialRemovalProposalIds[_officialAddress];

            // Emit event for official removal
            emit Events.OfficialRemoved(_orgId, _officialAddress);
        } else {
            emit Events.RemovalVotedOn(_orgId, _officialAddress, _inFavor);
        }
    }
}
