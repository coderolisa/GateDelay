// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "../contracts/RoleManager.sol";

contract RoleManagerTest {
    RoleManager private roleManager;
    bytes32 private constant ADMIN = keccak256("ADMIN");
    bytes32 private constant MINTER = keccak256("MINTER");
    bytes32 private constant MINT_PERMISSION = keccak256("MINT_PERMISSION");
    address private constant USER = address(0xBEEF);
    address private constant OTHER = address(0xCAFE);

    function setUp() public {
        roleManager = new RoleManager();
    }

    function testCreateRole() public {
        roleManager.createRole(ADMIN, "Administrator");
        require(roleManager.roleExists(ADMIN), "Role should exist");
        require(keccak256(bytes(roleManager.getRoleName(ADMIN))) == keccak256(bytes("Administrator")), "Role name mismatch");
        require(roleManager.getRoleCount() == 1, "Role count mismatch");
        bytes32[] memory ids = roleManager.getRoleIds();
        require(ids.length == 1 && ids[0] == ADMIN, "Role IDs query mismatch");
    }

    function testAssignAndQueryRole() public {
        roleManager.createRole(ADMIN, "Administrator");
        roleManager.assignRole(ADMIN, USER);

        require(roleManager.hasRole(ADMIN, USER), "Assigned user should have role");
        bytes32[] memory roles = roleManager.getRolesForAccount(USER);
        require(roles.length == 1 && roles[0] == ADMIN, "Roles for account mismatch");

        address[] memory members = roleManager.getRoleMembers(ADMIN);
        require(members.length == 1 && members[0] == USER, "Role members mismatch");
    }

    function testRevokeRoleAssignment() public {
        roleManager.createRole(ADMIN, "Administrator");
        roleManager.assignRole(ADMIN, USER);
        roleManager.revokeRole(ADMIN, USER);

        require(!roleManager.hasRole(ADMIN, USER), "Role should be revoked");
        require(roleManager.getRolesForAccount(USER).length == 0, "User should have no roles");
        require(roleManager.getRoleMembers(ADMIN).length == 0, "Role should have no members");
    }

    function testGrantAndCheckPermissions() public {
        roleManager.createRole(MINTER, "Minter");
        roleManager.grantPermission(MINTER, MINT_PERMISSION);

        require(roleManager.hasPermission(MINTER, MINT_PERMISSION), "Permission should be granted");
        bytes32[] memory permissions = roleManager.getRolePermissions(MINTER);
        require(permissions.length == 1 && permissions[0] == MINT_PERMISSION, "Role permissions mismatch");
    }

    function testPermissionPropagationToAccount() public {
        roleManager.createRole(MINTER, "Minter");
        roleManager.grantPermission(MINTER, MINT_PERMISSION);
        roleManager.assignRole(MINTER, USER);

        require(roleManager.hasPermissionForAccount(USER, MINT_PERMISSION), "User should inherit permission from role");
        roleManager.revokeRole(MINTER, USER);
        require(!roleManager.hasPermissionForAccount(USER, MINT_PERMISSION), "Revoked user should no longer have permission");
    }

    function testRevokePermissionFromRole() public {
        roleManager.createRole(MINTER, "Minter");
        roleManager.grantPermission(MINTER, MINT_PERMISSION);
        roleManager.revokePermission(MINTER, MINT_PERMISSION);

        require(!roleManager.hasPermission(MINTER, MINT_PERMISSION), "Permission should be revoked");
        require(roleManager.getRolePermissions(MINTER).length == 0, "Role permissions should be empty after revocation");
    }

    function testAssignDuplicateRoleReverts() public {
        roleManager.createRole(ADMIN, "Administrator");
        roleManager.assignRole(ADMIN, USER);
        bool didRevert = false;
        try roleManager.assignRole(ADMIN, USER) {
        } catch {
            didRevert = true;
        }
        require(didRevert, "Duplicate assignment should revert");
    }

    function testRevokeNonAssignedRoleReverts() public {
        roleManager.createRole(ADMIN, "Administrator");
        bool didRevert = false;
        try roleManager.revokeRole(ADMIN, USER) {
        } catch {
            didRevert = true;
        }
        require(didRevert, "Revoking non-assigned role should revert");
    }

    function testRoleQueriesReturnEmptyArraysForUnknownAccount() public {
        roleManager.createRole(ADMIN, "Administrator");
        bytes32[] memory roles = roleManager.getRolesForAccount(OTHER);
        require(roles.length == 0, "Unknown account roles should be empty");
    }
}
