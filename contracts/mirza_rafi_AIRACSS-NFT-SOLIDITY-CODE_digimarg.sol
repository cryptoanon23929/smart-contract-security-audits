// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

interface IERC20 {
    function transferFrom(address sender, address recipient, uint256 amount) external returns (bool);
}

contract DigitalMargeNFT {
    string public name = "Digital Marge";
    string public symbol = "ADMAEG";

    uint256 public constant MAX_SUPPLY = 500;
    uint256 public constant PRICE = 1 * 10**18;
    uint256 public totalSupply;

    IERC20 public AIRACSS = IERC20(0x7D73fF735E210ab1Da50D931FDA899154f646E80);
    address public treasury = 0x3a755E8E54D4167212F315fC17E49CE57334c952;

    string private baseURI = "https://bronze-active-bass-658.mypinata.cloud/ipfs/bafybeigw5gcyarf4qtbfbzpvxb527vidm4b6gi64y3fesbaht7raearuf4/";

    mapping(uint256 => address) private owners;
    mapping(address => uint256) public walletMinted;

    event Transfer(address indexed from, address indexed to, uint256 indexed tokenId);

    function mint(uint256 amount) external {
        require(amount > 0 && amount <= 2, "Mint 1-2 only");
        require(totalSupply + amount <= MAX_SUPPLY, "Sold out");
        require(walletMinted[msg.sender] + amount <= 2, "Wallet limit exceeded");

        require(AIRACSS.transferFrom(msg.sender, treasury, PRICE * amount), "Payment failed");

        for (uint256 i = 0; i < amount; i++) {
            uint256 tokenId = totalSupply + 1;
            owners[tokenId] = msg.sender;
            emit Transfer(address(0), msg.sender, tokenId);
            totalSupply++;
        }

        walletMinted[msg.sender] += amount;
    }

    function ownerOf(uint256 tokenId) public view returns (address) {
        require(tokenId > 0 && tokenId <= totalSupply, "Invalid tokenId");
        return owners[tokenId];
    }

    function tokenURI(uint256 tokenId) public view returns (string memory) {
        return string(abi.encodePacked(baseURI, uint2str(tokenId), ".json"));
    }

    function transferFrom(address from, address to, uint256 tokenId) public {
        require(ownerOf(tokenId) == from, "Not owner");
        require(msg.sender == from, "Only owner may transfer");
        owners[tokenId] = to;
        emit Transfer(from, to, tokenId);
    }

    function uint2str(uint256 _i) internal pure returns (string memory) {
        if (_i == 0) return "0";
        uint256 j = _i;
        uint256 len;
        while (j != 0) { len++; j /= 10; }
        bytes memory bstr = new bytes(len);
        uint256 k = len;
        j = _i;
        while (j != 0) {
            bstr[--k] = bytes1(uint8(48 + j % 10));
            j /= 10;
        }
        return string(bstr);
    }
}