// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;


contract SheepI{
   function walletOfOwner(address _owner) public view returns (uint256[] memory) {}
   function _exists(uint256 tokenId) internal view returns (bool) {}
}

contract Vote{
	
	address SheepContractAddress = 0x9E30Fb175abacc42B93225E208E809968C23029E;
	address ownerAddress;

	SheepI SheepC;

	struct aVote{
		address wallet;
		uint256 tokenId;
		uint256 IPNum;
		bool vote;
	}
	aVote[] votes;

	mapping(uint256 => bool) public alreadyVoted;	
	uint256[] private voted;
	bool public activeVote;
	uint256 public IPNum;	
	uint256 public numVotesCast = 0;

	event voteCast(address _address, bool _vote);
	event allVotes(aVote[] _votes);

	constructor() {
        SheepC = SheepI(SheepContractAddress);
        ownerAddress = msg.sender;
        activeVote = false;
        IPNum = 2;
    }


   function castVote(bool _vote) public returns(uint256){
   		require(activeVote, "No Proposal is being voted on");
   		require(msg.sender != address(0), "not valid signer");

   		//get owned sheep 
   		uint256[] memory tokenIds = SheepC.walletOfOwner(msg.sender);
   		uint256 numOwned = tokenIds.length;

	 		// find available votes (owned sheep that haven't voted)
   		uint256 numVotesAvailable = 0;
   		for(uint256 i=0; i<numOwned; ++i){
   			if( alreadyVoted[tokenIds[i]] == false){   			
   				++numVotesAvailable;
				}
   		}   			
   		require(numVotesAvailable > 0, "no votes for you");

   		//cast vote
   		//store vote in struct
   		//store tokenId in voted as reference for mapping deletion on new vote
   		for(uint i=0; i<numOwned; ++i){
   			if(alreadyVoted[tokenIds[i]] == false){
   				aVote memory vote = aVote(msg.sender, tokenIds[i], IPNum, _vote);
   				votes.push(vote);
   				voted.push(tokenIds[i]);
   				alreadyVoted[tokenIds[i]] = true;
   			}
   		}
	
			return numVotesAvailable;
   }

   //return all votes for specific proposal (_IPNum); true = yes, false = no
   function getVoteResult(uint256 _IPNum) public view returns(address[] memory, uint256[] memory, bool[] memory){

   	uint256 numVotes = 0;
   	for(uint256 i=0; i<votes.length; ++i){
   		if(votes[i].IPNum == _IPNum){
   			++numVotes;
   		}
   	}
   	address[] memory voteAddress = new address[](numVotes);
   	uint256[] memory voteTokenId = new uint256[](numVotes);
   	uint256[] memory voteIpNum = new uint256[](numVotes);
   	bool[] memory voteVote = new bool[](numVotes);

   	uint256 cnt=0;
   	for(uint256 i=0; i<votes.length; ++i){
   		if(votes[i].IPNum == _IPNum){
	   		voteAddress[cnt] = votes[i].wallet;
	   		voteTokenId[cnt] = votes[i].tokenId;
	   		voteIpNum[cnt] = votes[i].IPNum;
	   		voteVote[cnt] = votes[i].vote;
	   		++cnt;
	   	}
   	}

   	return(voteAddress,voteTokenId,voteVote);
   }


   //only Owner---------------------
   //increment Proposal Number
   //clear storage of who voted in mapping and array (not clearing vote storage in struct)
   function newVote() public {
      require( keccak256(abi.encodePacked(msg.sender)) == keccak256(abi.encodePacked(ownerAddress)), "only Owner can reset the vote");    
      ++IPNum;

      for(uint256 i=0; i<voted.length; ++i){
      	delete alreadyVoted[voted[i]];
      }

      delete voted;
   }

   //start / stop vote
   function toggleVote(bool _state) public {
   	require( keccak256(abi.encodePacked(msg.sender)) == keccak256(abi.encodePacked(ownerAddress)), "only Owner can start the vote");    
   	activeVote = _state;
   }

}
