// SPDX-License-Identifier: Unlicense
pragma solidity >=0.8.0;

import {DSTest} from "ds-test/test.sol";
import {Utilities} from "./utils/Utilities.sol";
import {console} from "./utils/Console.sol";
import {Vm} from "forge-std/Vm.sol";
import "src/AuctionFactory.sol";

contract ContractTest is DSTest {
    Vm internal immutable vm = Vm(HEVM_ADDRESS);

    Utilities internal utils;
    address payable[] internal users;

    function setUp() public {
        utils = new Utilities();
        users = utils.createUsers(5);
    }

    function testExample() public {
        AuctionFactory factory = new AuctionFactory(address(0), address(0), address(0), address(0));
    }
}
