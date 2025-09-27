// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

/// @title Disperse - bulk send ETH and ERC20 tokens
/// @notice Minimal, audited-style contract to disperse ERC20 tokens and ETH to many recipients.
/// User approves the contract for the total token amount, then calls disperseToken.
/// Includes basic protections and recovery functions.

interface IERC20 {
    function totalSupply() external view returns (uint256);
    function balanceOf(address account) external view returns (uint256);
    function transfer(address to, uint256 amount) external returns (bool);
    function allowance(address owner, address spender) external view returns (uint256);
    function approve(address spender, uint256 amount) external returns (bool);
    function transferFrom(address from, address to, uint256 amount) external returns (bool);
}

library SafeERC20 {
    function safeTransfer(IERC20 token, address to, uint256 value) internal {
        _callOptionalReturn(token, abi.encodeWithSelector(token.transfer.selector, to, value));
    }

    function safeTransferFrom(IERC20 token, address from, address to, uint256 value) internal {
        _callOptionalReturn(token, abi.encodeWithSelector(token.transferFrom.selector, from, to, value));
    }

    function _callOptionalReturn(IERC20 token, bytes memory data) private {
        (bool success, bytes memory returndata) = address(token).call(data);
        require(success, "SafeERC20: low-level call failed");
        if (returndata.length > 0) { // Return data is optional
            // Tokens that return a boolean will return true on success
            require(abi.decode(returndata, (bool)), "SafeERC20: ERC20 operation did not succeed");
        }
    }
}

/// @dev Minimal reentrancy guard
abstract contract ReentrancyGuard {
    uint256 private constant _NOT_ENTERED = 1;
    uint256 private constant _ENTERED = 2;
    uint256 private _status;

    constructor() { _status = _NOT_ENTERED; }

    modifier nonReentrant() {
        require(_status != _ENTERED, "ReentrancyGuard: reentrant call");
        _status = _ENTERED;
        _;
        _status = _NOT_ENTERED;
    }
}

contract Disperse is ReentrancyGuard {
    using SafeERC20 for IERC20;

    address public owner;

    event EtherDispersed(address indexed sender, uint256 total, uint256 count);
    event TokenDispersed(address indexed sender, address indexed token, uint256 total, uint256 count);
    event WithdrawnToken(address indexed token, address indexed to, uint256 amount);
    event WithdrawnEther(address indexed to, uint256 amount);

    modifier onlyOwner() {
        require(msg.sender == owner, "Only owner");
        _;
    }

    constructor() {
        owner = msg.sender;
    }

    /// @notice Disperse ETH to many recipients in one transaction
    /// @param recipients array of recipient addresses
    /// @param amounts array of amounts in wei for each recipient
    /// Requirements:
    /// - recipients.length == amounts.length
    /// - sum(amounts) == msg.value
    function disperseEther(address[] calldata recipients, uint256[] calldata amounts) external payable nonReentrant {
        uint256 len = recipients.length;
        require(len == amounts.length, "Length mismatch");
        uint256 total = 0;
        for (uint256 i = 0; i < len; ) {
            total += amounts[i];
            unchecked { i++; }
        }
        require(total == msg.value, "Value mismatch");

        // send
        for (uint256 i = 0; i < len; ) {
            (bool ok, ) = recipients[i].call{value: amounts[i]}("");
            require(ok, "ETH transfer failed");
            unchecked { i++; }
        }

        emit EtherDispersed(msg.sender, total, len);
    }

    /// @notice Disperse ERC20 tokens to many recipients. Caller must approve the contract for the total amount first.
    /// @param token ERC20 token address
    /// @param recipients array of recipient addresses
    /// @param amounts array of token amounts for each recipient
    function disperseToken(address token, address[] calldata recipients, uint256[] calldata amounts) external nonReentrant {
        uint256 len = recipients.length;
        require(len == amounts.length, "Length mismatch");
        uint256 total = 0;
        for (uint256 i = 0; i < len; ) {
            total += amounts[i];
            unchecked { i++; }
        }
        require(total > 0, "Zero total");

        IERC20 erc = IERC20(token);

        // Pull tokens from sender to this contract in a single transferFrom to save gas
        // Note: some tokens may not allow pulling the full amount in one call if they have special logic;
        // in that rare case the caller can manually transfer tokens to the contract and then call `disperseTokenFromContract`.
        erc.transferFrom(msg.sender, address(this), total);

        // distribute
        for (uint256 i = 0; i < len; ) {
            erc.transfer(recipients[i], amounts[i]);
            unchecked { i++; }
        }

        emit TokenDispersed(msg.sender, token, total, len);
    }

    /// @notice Alternative: if caller has already sent tokens to this contract, call this to distribute from contract balance
    function disperseTokenFromContract(address token, address[] calldata recipients, uint256[] calldata amounts) external nonReentrant {
        uint256 len = recipients.length;
        require(len == amounts.length, "Length mismatch");
        uint256 total = 0;
        for (uint256 i = 0; i < len; ) {
            total += amounts[i];
            unchecked { i++; }
        }
        require(total > 0, "Zero total");

        IERC20 erc = IERC20(token);
        uint256 contractBal = erc.balanceOf(address(this));
        require(contractBal >= total, "Insufficient contract token balance");

        for (uint256 i = 0; i < len; ) {
            erc.transfer(recipients[i], amounts[i]);
            unchecked { i++; }
        }

        emit TokenDispersed(msg.sender, token, total, len);
    }

    // --- Recovery / admin functions ---

    /// @notice Withdraw tokens accidentally sent to contract
    function withdrawToken(address token, address to, uint256 amount) external onlyOwner {
        IERC20(token).transfer(to, amount);
        emit WithdrawnToken(token, to, amount);
    }

    /// @notice Withdraw ETH accidentally sent to contract
    function withdrawEther(address payable to, uint256 amount) external onlyOwner {
        (bool ok, ) = to.call{value: amount}("");
        require(ok, "ETH withdraw failed");
        emit WithdrawnEther(to, amount);
    }

    /// @notice Change owner
    function setOwner(address newOwner) external onlyOwner {
        require(newOwner != address(0), "Zero address");
        owner = newOwner;
    }

    // Allow contract to receive ETH
    receive() external payable {}
    fallback() external payable {}
}
