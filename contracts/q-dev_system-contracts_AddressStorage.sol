// SPDX-License-Identifier: LGPL-3.0-or-later
// solium-disable linebreak-style
pragma solidity 0.8.9;

import "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";

contract AddressStorage is OwnableUpgradeable {
    struct Index {
        uint256 id;
    }
    mapping(address => Index) internal map;
    address[] internal addrList;

    constructor() {}

    function initialize(address[] memory _addrList) external virtual initializer {
        for (uint256 i = 0; i < _addrList.length; i++) {
            if (map[_addrList[i]].id > 0) continue;
            addrList.push(_addrList[i]);
            map[_addrList[i]].id = addrList.length;
        }
        __Ownable_init();
    }

    /**
     * @notice remove address if it is in storage, reverts if address is not in storage
     * @param _addr address to remove
     */
    function mustRemove(address _addr) external {
        require(remove(_addr), "[QEC-035000]-Failed to remove the address from the address storage.");
    }

    /**
     * @notice Returns count of addresses
     * @return count of addresses
     */
    function size() external view returns (uint256) {
        return addrList.length;
    }

    /**
     * @return array of stored addresses
     */
    function getAddresses() external view returns (address[] memory) {
        return addrList;
    }

    /**
     * @notice add address if it is in storage, reverts if address in storage
     * @param _addr address to add
     */
    function mustAdd(address _addr) public {
        require(
            add(_addr),
            "[QEC-035002]-The address has already been added to the storage, "
            "failed to add the address to the address storage."
        );
    }

    /**
     * @notice add address if it is not in storage
     * @param _addr address to add
     * @return true if address was added
     */
    function add(address _addr) public onlyOwner returns (bool) {
        if (contains(_addr)) {
            return false;
        }
        _add(_addr);
        return true;
    }

    /**
     * @notice remove address if it is in storage
     * @param _addr address to remove
     * @return true if address was removed
     */
    function remove(address _addr) public onlyOwner returns (bool) {
        if (!contains(_addr)) {
            return false;
        }
        _remove(_addr);
        return true;
    }

    /**
     * @notice remove all addresses
     * @return true if all addresses were removed
     */
    function clear() public onlyOwner returns (bool) {
        for (uint256 i = 0; i < addrList.length; i++) {
            delete map[addrList[i]];
        }
        delete addrList;
        return true;
    }

    /**
     * @notice checks availability of address
     * @param _addr address to check
     * @return true if address in storage
     */
    function contains(address _addr) public view returns (bool) {
        uint256 _id = map[_addr].id;
        return _id > 0;
    }

    function _add(address _addr) private {
        addrList.push(_addr);
        map[_addr].id = addrList.length;

        _checkEntry(_addr);
    }

    function _remove(address _addr) private {
        Index memory index = map[_addr];

        // Move an last element of array into the vacated key slot.
        uint256 lastListID = addrList.length - 1;
        address lastListAddress = addrList[lastListID];
        if (lastListID != index.id - 1) {
            map[lastListAddress].id = index.id;
            addrList[index.id - 1] = lastListAddress;
        }
        addrList.pop();
        delete map[_addr];

        _checkEntry(_addr);

        if (lastListAddress != _addr) _checkEntry(lastListAddress);
    }

    function _checkEntry(address _addr) private view {
        uint256 _id = map[_addr].id;
        assert(_id <= addrList.length); // "Map contains wrong id"
        if (contains(_addr))
            assert(_id > 0); // "index start with 1, so included elements must have index > 0"
        else assert(_id == 0); // non included elements must have index 0
    }
}
