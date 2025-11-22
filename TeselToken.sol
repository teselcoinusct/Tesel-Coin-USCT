// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "https://github.com/OpenZeppelin/openzeppelin-contracts/blob/v4.9.3/contracts/token/ERC20/ERC20.sol";
import "https://github.com/OpenZeppelin/openzeppelin-contracts/blob/v4.9.3/contracts/security/Pausable.sol";
import "https://github.com/OpenZeppelin/openzeppelin-contracts/blob/v4.9.3/contracts/access/Ownable.sol";

interface IUpgradedStandardToken {
    function transferByLegacy(address from, address to, uint256 value) external;
    function transferFromByLegacy(address caller, address from, address to, uint256 value) external;
    function approveByLegacy(address from, address spender, uint256 value) external;
    function balanceOf(address who) external view returns (uint256);
    function totalSupply() external view returns (uint256);
    function allowance(address owner, address spender) external view returns (uint256);
}

contract TeselToken is ERC20, Ownable, Pausable {
    uint256 public basisPointsRate;
    uint256 public maximumFee;
    mapping(address => bool) public isBlackListed;

    address public upgradedAddress;
    bool public deprecated;

    uint256 public immutable maxSupply;
    uint8 private _decimals;

    event Params(uint256 feeBP, uint256 maxFee);
    event AddedBlackList(address user);
    event RemovedBlackList(address user);
    event DestroyedBlackFunds(address user, uint256 amount);
    event Deprecate(address newAddress);

    constructor(
        string memory name_,
        string memory symbol_,
        uint8 decimals_
    ) ERC20(name_, symbol_) {
        _decimals = decimals_;
        maxSupply = 150_000_000_000 * (10 ** decimals_);
        _mint(msg.sender, maxSupply);
    }

    function decimals() public view override returns (uint8) {
        return _decimals;
    }

    function _transfer(address from, address to, uint256 amount) internal override {
        require(!paused(), "paused");
        require(!isBlackListed[from], "blacklisted");

        if (deprecated && upgradedAddress != address(0)) {
            IUpgradedStandardToken(upgradedAddress).transferByLegacy(from, to, amount);
            return;
        }

        uint256 fee = (amount * basisPointsRate) / 10000;
        if (fee > maximumFee) fee = maximumFee;
        uint256 sendAmt = amount - fee;

        super._transfer(from, to, sendAmt);
        if (fee > 0) super._transfer(from, owner(), fee);
    }

    function transferFrom(address from, address to, uint256 amount) public override returns (bool) {
        require(!paused(), "paused");
        require(!isBlackListed[from], "blacklisted");

        if (deprecated && upgradedAddress != address(0)) {
            IUpgradedStandardToken(upgradedAddress).transferFromByLegacy(msg.sender, from, to, amount);
            return true;
        }

        uint256 allowed = allowance(from, msg.sender);
        require(allowed >= amount, "allowance");

        if (allowed != type(uint256).max) _approve(from, msg.sender, allowed - amount);

        _transfer(from, to, amount);
        return true;
    }

    function approve(address spender, uint256 amount) public override returns (bool) {
        if (deprecated && upgradedAddress != address(0)) {
            IUpgradedStandardToken(upgradedAddress).approveByLegacy(msg.sender, spender, amount);
            return true;
        }
        return super.approve(spender, amount);
    }

    function totalSupply() public view override returns (uint256) {
        if (deprecated && upgradedAddress != address(0))
            return IUpgradedStandardToken(upgradedAddress).totalSupply();
        return super.totalSupply();
    }

    function balanceOf(address a) public view override returns (uint256) {
        if (deprecated && upgradedAddress != address(0))
            return IUpgradedStandardToken(upgradedAddress).balanceOf(a);
        return super.balanceOf(a);
    }

    function allowance(address o, address s) public view override returns (uint256) {
        if (deprecated && upgradedAddress != address(0))
            return IUpgradedStandardToken(upgradedAddress).allowance(o, s);
        return super.allowance(o, s);
    }

    // ---------- Owner functions ----------
    function deprecate(address up) external onlyOwner {
        deprecated = true;
        upgradedAddress = up;
        emit Deprecate(up);
    }

    function setParams(uint256 bp, uint256 maxFee_) external onlyOwner {
        require(bp < 20, "bp<20");
        basisPointsRate = bp;
        maximumFee = maxFee_;
        emit Params(bp, maxFee_);
    }

    function pause() external onlyOwner { _pause(); }
    function unpause() external onlyOwner { _unpause(); }

    function addBlackList(address u) external onlyOwner {
        isBlackListed[u] = true; emit AddedBlackList(u);
    }

    function removeBlackList(address u) external onlyOwner {
        isBlackListed[u] = false; emit RemovedBlackList(u);
    }

    function destroyBlackFunds(address u) external onlyOwner {
        uint256 bal = balanceOf(u);
        require(isBlackListed[u] && bal > 0, "invalid");
        _burn(u, bal);
        emit DestroyedBlackFunds(u, bal);
    }

    function redeem(uint256 amt) external onlyOwner {
        _burn(owner(), amt);
    }

    // enforce cap
    function _mint(address a, uint256 amt) internal override {
        require(totalSupply() + amt <= maxSupply, "cap");
        super._mint(a, amt);
    }

    function recoverERC20(address token, uint256 amt) external onlyOwner {
        require(token != address(this), "no");
        IERC20(token).transfer(owner(), amt);
    }
}
