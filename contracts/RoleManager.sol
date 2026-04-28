// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

/// @notice Ownable implementation compatible with OpenZeppelin patterns.
abstract contract Context {
    function _msgSender() internal view virtual returns (address) {
        return msg.sender;
    }

    function _msgData() internal view virtual returns (bytes calldata) {
        return msg.data;
    }
}

abstract contract Ownable is Context {
    address private _owner;

    event OwnershipTransferred(address indexed previousOwner, address indexed newOwner);

    constructor() {
        _transferOwnership(_msgSender());
    }

    modifier onlyOwner() {
        require(owner() == _msgSender(), "Ownable: caller is not the owner");
        _;
    }

    function owner() public view virtual returns (address) {
        return _owner;
    }

    function transferOwnership(address newOwner) public virtual onlyOwner {
        require(newOwner != address(0), "Ownable: new owner is the zero address");
        _transferOwnership(newOwner);
    }

    function _transferOwnership(address newOwner) internal virtual {
        address oldOwner = _owner;
        _owner = newOwner;
        emit OwnershipTransferred(oldOwner, newOwner);
    }
}

contract RoleManager is Ownable {
    struct Role {
        string name;
        bool exists;
        address[] members;
        mapping(address => bool) memberSet;
        bytes32[] permissions;
        mapping(bytes32 => bool) permissionSet;
    }

    bytes32[] private _roleIds;
    mapping(bytes32 => Role) private _roles;
    mapping(address => bytes32[]) private _accountRoles;
    mapping(address => mapping(bytes32 => bool)) private _hasRole;

    event RoleCreated(bytes32 indexed roleId, string name);
    event RoleAssigned(bytes32 indexed roleId, address indexed account);
    event RoleRevoked(bytes32 indexed roleId, address indexed account);
    event PermissionGranted(bytes32 indexed roleId, bytes32 indexed permission);
    event PermissionRevoked(bytes32 indexed roleId, bytes32 indexed permission);

    error RoleAlreadyExists(bytes32 roleId);
    error RoleNotFound(bytes32 roleId);
    error AlreadyHasRole(bytes32 roleId, address account);
    error MissingRole(bytes32 roleId, address account);
    error PermissionAlreadyExists(bytes32 roleId, bytes32 permission);
    error PermissionDoesNotExist(bytes32 roleId, bytes32 permission);

    modifier onlyExistingRole(bytes32 roleId) {
        if (!_roles[roleId].exists) revert RoleNotFound(roleId);
        _;
    }

    /// @notice Create a new role with a unique ID and a human-readable name.
    function createRole(bytes32 roleId, string calldata name) external onlyOwner {
        if (_roles[roleId].exists) revert RoleAlreadyExists(roleId);
        _roles[roleId].exists = true;
        _roles[roleId].name = name;
        _roleIds.push(roleId);
        emit RoleCreated(roleId, name);
    }

    /// @notice Assign a role to an account.
    function assignRole(bytes32 roleId, address account) external onlyOwner onlyExistingRole(roleId) {
        if (_hasRole[account][roleId]) revert AlreadyHasRole(roleId, account);
        _roles[roleId].memberSet[account] = true;
        _roles[roleId].members.push(account);
        _accountRoles[account].push(roleId);
        _hasRole[account][roleId] = true;
        emit RoleAssigned(roleId, account);
    }

    /// @notice Revoke a role from an account.
    function revokeRole(bytes32 roleId, address account) external onlyOwner onlyExistingRole(roleId) {
        if (!_hasRole[account][roleId]) revert MissingRole(roleId, account);
        _removeRoleMember(roleId, account);
        _removeAccountRole(account, roleId);
        _hasRole[account][roleId] = false;
        emit RoleRevoked(roleId, account);
    }

    /// @notice Grant a permission to a role.
    function grantPermission(bytes32 roleId, bytes32 permission) external onlyOwner onlyExistingRole(roleId) {
        if (_roles[roleId].permissionSet[permission]) revert PermissionAlreadyExists(roleId, permission);
        _roles[roleId].permissionSet[permission] = true;
        _roles[roleId].permissions.push(permission);
        emit PermissionGranted(roleId, permission);
    }

    /// @notice Revoke a permission from a role.
    function revokePermission(bytes32 roleId, bytes32 permission) external onlyOwner onlyExistingRole(roleId) {
        if (!_roles[roleId].permissionSet[permission]) revert PermissionDoesNotExist(roleId, permission);
        _roles[roleId].permissionSet[permission] = false;
        _removePermission(roleId, permission);
        emit PermissionRevoked(roleId, permission);
    }

    /// @notice Check whether an account has a specific role.
    function hasRole(bytes32 roleId, address account) public view returns (bool) {
        return _hasRole[account][roleId];
    }

    /// @notice Check whether a role has a specific permission.
    function hasPermission(bytes32 roleId, bytes32 permission) public view onlyExistingRole(roleId) returns (bool) {
        return _roles[roleId].permissionSet[permission];
    }

    /// @notice Check whether any role assigned to an account grants a permission.
    function hasPermissionForAccount(address account, bytes32 permission) public view returns (bool) {
        bytes32[] storage roles = _accountRoles[account];
        for (uint256 i = 0; i < roles.length; i++) {
            if (_roles[roles[i]].permissionSet[permission]) {
                return true;
            }
        }
        return false;
    }

    /// @notice Get the human-readable name of a role.
    function getRoleName(bytes32 roleId) public view onlyExistingRole(roleId) returns (string memory) {
        return _roles[roleId].name;
    }

    /// @notice Get all registered role identifiers.
    function getRoleIds() public view returns (bytes32[] memory) {
        return _roleIds;
    }

    /// @notice Get all roles currently assigned to an account.
    function getRolesForAccount(address account) public view returns (bytes32[] memory) {
        return _accountRoles[account];
    }

    /// @notice Get all accounts assigned to a specific role.
    function getRoleMembers(bytes32 roleId) public view onlyExistingRole(roleId) returns (address[] memory) {
        return _roles[roleId].members;
    }

    /// @notice Get all permissions granted to a specific role.
    function getRolePermissions(bytes32 roleId) public view onlyExistingRole(roleId) returns (bytes32[] memory) {
        return _roles[roleId].permissions;
    }

    /// @notice Check whether a role exists.
    function roleExists(bytes32 roleId) public view returns (bool) {
        return _roles[roleId].exists;
    }

    /// @notice Get the total number of roles created.
    function getRoleCount() external view returns (uint256) {
        return _roleIds.length;
    }

    function _removeRoleMember(bytes32 roleId, address account) private {
        Role storage role = _roles[roleId];
        delete role.memberSet[account];
        address[] storage members = role.members;
        for (uint256 i = 0; i < members.length; i++) {
            if (members[i] == account) {
                members[i] = members[members.length - 1];
                members.pop();
                return;
            }
        }
    }

    function _removeAccountRole(address account, bytes32 roleId) private {
        bytes32[] storage roles = _accountRoles[account];
        for (uint256 i = 0; i < roles.length; i++) {
            if (roles[i] == roleId) {
                roles[i] = roles[roles.length - 1];
                roles.pop();
                return;
            }
        }
    }

    function _removePermission(bytes32 roleId, bytes32 permission) private {
        bytes32[] storage permissions = _roles[roleId].permissions;
        for (uint256 i = 0; i < permissions.length; i++) {
            if (permissions[i] == permission) {
                permissions[i] = permissions[permissions.length - 1];
                permissions.pop();
                return;
            }
        }
    }
}
