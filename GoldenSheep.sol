// SPDX-License-Identifier: MIT

pragma solidity >=0.8.0;

import "@openzeppelin/contracts/token/ERC721/extensions/ERC721Enumerable.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/utils/Strings.sol";
import "@openzeppelin/contracts/utils/cryptography/ECDSA.sol";
import "hardhat/console.sol";

contract PixelSheep is ERC721Enumerable, Ownable {
    using Strings for uint256;

    bool public paused = true; 
    bool public onlyWhitelisted = true;
    uint256 public cost = 583000000000000000000;//583 tfuel in wei
    uint256 public maxSupply = 4242;
    uint256 public maxMintAmount = 5;
    uint256 public nftPerAddressLimit = 10;
    uint256 public ownerMinted = 0; //track premint balance
    uint256 public burnt = 0; //track number of burnt sheep
    string public baseURI;
    mapping(address => uint256) public addressMintedBalance;

    address public wolfContract = 0x0000000000000000000000000000000000000000;// contract of next NFT release - assigned through onlyOwner function
   
    //For gasless whitelist
    address private mintPass_publickey;
    struct MintPass {
        address message; //contains whitelisted user's public key + salt
        bytes32 r;
        bytes32 s;
        uint8 v;
    }

    event Minted(address addr, string message);

    constructor(
        string memory _name,
        string memory _symbol,
        string memory _initBaseURI, 
        address _mintPass_publickey
    ) ERC721(_name, _symbol) {
        setBaseURI(_initBaseURI);
        setMintPassPublicKey(_mintPass_publickey); //set keypair half to verify mintPass
    }

    // PUBLIC***********
    // front end passes a predetermined MintPass(json) that contains hash of user's address 
    // signed with an off chain admin keypair to verify whitelist status
    // verify # minting, supply, whitelist, cost and mint
    function mint(MintPass memory _mintPass, uint256 _mintAmount) public payable {
        require(!paused, "the contract is paused");
        uint256 numAlreadyMinted = totalSupply(); 
        require(_mintAmount > 0, "you need to mint at least 1 NFT");
        require(_mintAmount <= maxMintAmount, "max mint amount per session exceeded" );
        require(numAlreadyMinted + _mintAmount <= maxSupply, "There aren't this many NFTs left.");

        if (onlyWhitelisted == true) {
            //hash senders address to validate whitelist status
            bytes32 digest = keccak256(abi.encode(0, msg.sender));
            //verify mintpass
            require(approveSender(digest, _mintPass), "MintPass missing or invalid" );
        }

        //verify NFTs owned after proposed mint is less than max allowed
        require(addressMintedBalance[msg.sender] + _mintAmount <= nftPerAddressLimit, "max NFT per address exceeded" );
        
        //check funds and mint
        require(msg.value >= cost * _mintAmount, "Insufficient funds");
        for (uint256 i = 1; i <= _mintAmount; i++) {
            addressMintedBalance[msg.sender]++;
            _safeMint(msg.sender, numAlreadyMinted + i);
        }
    }

    // returns avaialable, max supply, and # burnt for front end display
    function howMany() public view returns (string memory, string memory, string memory) {
        uint256 remaining = maxSupply - totalSupply();
        return (Strings.toString(maxSupply), Strings.toString(remaining), Strings.toString(burnt));
    }

    // return token IDs of current wallet
    function walletOfOwner(address _owner) public view returns (uint256[] memory) {
        uint256 ownerTokenCount = balanceOf(_owner);
        uint256[] memory tokenIds = new uint256[](ownerTokenCount);
        for (uint256 i; i < ownerTokenCount; i++) {
            tokenIds[i] = tokenOfOwnerByIndex(_owner, i);
        }
        return tokenIds;
    }

    // return token URI
    function tokenURI(uint256 _tokenId) public view virtual override returns (string memory){
        require( _exists(_tokenId), "ERC721Metadata: URI query for nonexistent token" );
        string memory currentBaseURI = _baseURI();
        string memory id = _pad(_tokenId - 1);
        return bytes(currentBaseURI).length > 0 ? string( abi.encodePacked( currentBaseURI, id, ".json" ) ) : "";
    }

    // PRIVATE***********
    // validate MintPass, off chain transaction signed by admin keypair
    // mintpass included message == msg.sender & signer == adminKey
    function approveSender(bytes32 _digest, MintPass memory _mintPass) private view returns (bool) {
        address signer = ecrecover(_digest, _mintPass.v, _mintPass.r, _mintPass.s);
        require(signer == mintPass_publickey, "MintPass invalid");
        bytes32 messageHash = keccak256(abi.encode(0, _mintPass.message));
        require( _digest == messageHash, "MintPass is not Valid for this address" );

        return true;
    }

    // ONLY OWNER***********
    // Premint 42 Sheep (includes giveaway sheep)
    function OwnerMint() public onlyOwner {
        if(ownerMinted < 42){
            uint256 numAlreadyMinted = totalSupply(); //0       
            for (uint256 i = numAlreadyMinted+1; i <= 42; i++) {
                addressMintedBalance[msg.sender]++;
                _safeMint(msg.sender, numAlreadyMinted + i);
                ownerMinted = ownerMinted + 1;
            }
        }
    }

    // adjust vars to end whitelist only event
    function fairMint(uint256 _cost) public onlyOwner(){
        nftPerAddressLimit = 40;
        maxMintAmount = 5;
        onlyWhitelisted = false;
        cost = _cost;
    }

    function setCost(uint256 _cost) public onlyOwner(){
        cost = _cost;
    }

    function setmaxMintAmount(uint256 _maxMintAmount) public onlyOwner(){
        maxMintAmount = _maxMintAmount;
    }

    // remove cap on wallet ownership after mint event
    function afterMintEvent() public onlyOwner{
        nftPerAddressLimit = 4242;
    }

    function setBaseURI(string memory _newBaseURI) public onlyOwner {
        baseURI = _newBaseURI;
    }

    function setMintPassPublicKey(address _mintPass_publickey) public onlyOwner{
        mintPass_publickey = _mintPass_publickey;
    } 

    function withdraw() public payable onlyOwner {
        (bool os, ) = payable(owner()).call{value: address(this).balance}("");
        require(os);
    }

    function pause(bool _state) public onlyOwner {
        paused = _state;
    }

    // so 43A 96B 374 411
    function setWolfContract(address _addy) public onlyOwner returns (address){
        wolfContract = _addy;
        return wolfContract;
    }


    // EXTERNAL *****
    // burn nft if function is called from registered contract by owner of a sheep
    function burnNFT(address _signer, uint256 _tokenId) external returns(bool){ 
        //check if token exists, if burn request is from the wolf contract, 
        //and if burn request initiator is token owner (passed from wolf contract)
        require( _exists(_tokenId), "This Sheep doesn't exist." );
        require( keccak256(abi.encodePacked(msg.sender)) == keccak256(abi.encodePacked(wolfContract)), "Only Wolves can eat Sheep.");    
        require( keccak256(abi.encodePacked(_signer)) == keccak256(abi.encodePacked(ownerOf(_tokenId))), "You cannot eat a sheep that you don't own");    

        _burn(_tokenId);
        burnt++;
        return true;
    }


    // INTERNAL *****
    function _baseURI() internal view virtual override returns (string memory) {
        return baseURI;
    }

    // pad token name with leading zeros to match file names
    function _pad(uint256 _n) internal view returns(string memory){
        string memory t;
        string memory z = "0";
        if (_n < 1000){
            if (_n < 10){
                t = string(abi.encodePacked(z, z, z, _n.toString()));
            }else if(_n<100){
                t = string(abi.encodePacked(z, z, _n.toString()));
            }else{
                t = string(abi.encodePacked(z, _n.toString()));
            }
        }else{
            t = _n.toString();
        }
        return t;
    }
}
