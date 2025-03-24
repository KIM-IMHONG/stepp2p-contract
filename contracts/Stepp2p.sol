// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.28;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";

contract Stepp2p is Ownable, ReentrancyGuard {
    struct Sale {
        address seller;
        uint256 totalAmount;
        uint256 remaining;
        bool active;
    }

    mapping(uint256 => Sale) public sales;
    mapping(address => uint256[]) public sellerSales;
    mapping(address => uint256) public lastSellerSaleId;
    uint256 public lastSaleId;
    uint256 public fee;
    address public feeAccount;
    IERC20 public USDT;

    event SaleRegistered(uint256 saleId, address seller, uint256 amount);
    event SaleCanceled(uint256 saleId);
    event SalePartiallyCompleted(uint256 saleId, address buyer, uint256 amount);
    event SaleModifyed(
        uint256 saleId,
        address seller,
        uint256 totalAmount,
        uint256 remaining
    );

    constructor(uint256 _fee, address _feeAccount) Ownable(msg.sender) {
        fee = _fee;
        feeAccount = _feeAccount;
    }

    function setUSDT(address _usdt) external onlyOwner {
        USDT = IERC20(_usdt);
    }

    // 5% = 50
    function setFee(uint256 _fee) external onlyOwner {
        fee = _fee;
    }

    function setFeeAccount(address _feeAccount) external onlyOwner {
        feeAccount = _feeAccount;
    }

    function createSaleOrder(uint256 _amount) external nonReentrant {
        require(_amount > 0, "Amount must be greater than 0");
        lastSaleId++;

        USDT.transferFrom(msg.sender, address(this), _amount);

        uint256 feeAmount = (_amount * fee) / 1000;
        uint256 saleAmount = _amount - feeAmount;

        USDT.transfer(feeAccount, feeAmount);

        sales[lastSaleId] = Sale({
            seller: msg.sender,
            totalAmount: saleAmount,
            remaining: saleAmount,
            active: true
        });
        sellerSales[msg.sender].push(lastSaleId);
        lastSellerSaleId[msg.sender] = lastSaleId;

        emit SaleRegistered(lastSaleId, msg.sender, saleAmount);
    }

    function modifySaleOrder(
        uint256 _saleId,
        uint256 _modifyAmount,
        bool isPositive
    ) external nonReentrant {
        require(_modifyAmount > 0, "Amount must be greater than 0");
        require(sales[_saleId].seller == msg.sender);

        if (isPositive) {
            sales[_saleId].totalAmount += _modifyAmount;
            sales[_saleId].remaining += _modifyAmount;
            USDT.transferFrom(msg.sender, address(this), _modifyAmount);
        } else {
            sales[_saleId].totalAmount -= _modifyAmount;
            sales[_saleId].remaining -= _modifyAmount;
            USDT.transfer(msg.sender, _modifyAmount);
        }

        emit SaleModifyed(
            _saleId,
            msg.sender,
            sales[_saleId].totalAmount,
            sales[_saleId].remaining
        );
    }

    function cancelSaleOrder(uint256 _saleId) external nonReentrant {
        Sale storage sale = sales[_saleId];
        require(
            sale.seller == msg.sender || msg.sender == owner(),
            "Not authorized"
        );
        require(sale.remaining > 0 && sale.active, "Invalid sale");

        uint256 refundAmount = sale.remaining;
        sale.active = false; // 상태 먼저 변경 후

        require(USDT.transfer(sale.seller, refundAmount), "Refund failed");
        emit SaleCanceled(_saleId);
    }

    function cancelSelectedSales(
        uint256[] calldata saleIds
    ) external nonReentrant {
        uint256 totalRefund = 0;
        for (uint256 i = 0; i < saleIds.length; i++) {
            Sale storage sale = sales[saleIds[i]];
            require(sale.seller == msg.sender, "Not your sale");
            if (sale.active && sale.remaining > 0) {
                sale.active = false;
                totalRefund += sale.remaining;
                emit SaleCanceled(saleIds[i]);
            }
        }
        if (totalRefund > 0) {
            USDT.transfer(msg.sender, totalRefund);
        }
    }

    function cancelSelectedSales(
        address seller,
        uint256[] calldata saleIds
    ) external nonReentrant onlyOwner {
        uint256 totalRefund = 0;
        for (uint256 i = 0; i < saleIds.length; i++) {
            Sale storage sale = sales[saleIds[i]];
            require(sale.seller == seller, "Not your sale");
            if (sale.active && sale.remaining > 0) {
                sale.active = false;
                totalRefund += sale.remaining;
                emit SaleCanceled(saleIds[i]);
            }
        }
        if (totalRefund > 0) {
            USDT.transfer(seller, totalRefund);
        }
    }

    function cancelAllSales() external nonReentrant {
        uint256[] storage saleIds = sellerSales[msg.sender];
        uint256 totalRefund = 0;

        for (uint256 i = 0; i < saleIds.length; i++) {
            Sale storage sale = sales[saleIds[i]];
            if (sale.active && sale.remaining > 0) {
                sale.active = false;
                totalRefund += sale.remaining;
                emit SaleCanceled(saleIds[i]);
            }
        }

        if (totalRefund > 0) {
            USDT.transfer(msg.sender, totalRefund);
        }
    }

    function cancelAllSales(address _seller) external nonReentrant onlyOwner {
        uint256[] storage saleIds = sellerSales[_seller];
        uint256 totalRefund = 0;

        for (uint256 i = 0; i < saleIds.length; i++) {
            Sale storage sale = sales[saleIds[i]];
            if (sale.active && sale.remaining > 0) {
                sale.active = false;
                totalRefund += sale.remaining;
                emit SaleCanceled(saleIds[i]);
            }
        }

        if (totalRefund > 0) {
            USDT.transfer(_seller, totalRefund);
        }
    }

    function purchase(
        uint256 _saleId,
        uint256 _amount,
        address buyer
    ) external nonReentrant onlyOwner {
        Sale storage sale = sales[_saleId];
        require(sale.active, "Sale inactive");
        require(_amount > 0 && _amount <= sale.remaining, "Invalid amount");

        sale.remaining -= _amount;

        uint256 feeAmount = (_amount * fee) / 1000;
        uint256 saleAmount = _amount - feeAmount;

        require(USDT.transfer(buyer, saleAmount), "Transfer failed");
        USDT.transfer(feeAccount, feeAmount);

        if (sale.remaining == 0) {
            sale.active = false;
        }

        emit SalePartiallyCompleted(_saleId, buyer, _amount);
    }

    function getTotalRemainingAmount(
        address _seller
    ) external view returns (uint256 totalRemaining) {
        uint256[] memory saleIds = sellerSales[_seller];
        for (uint256 i = 0; i < saleIds.length; i++) {
            Sale storage sale = sales[saleIds[i]];
            if (sale.active) {
                totalRemaining += sale.remaining;
            }
        }
    }

    function getRemainingSelectedAmount(
        uint256[] calldata saleIds
    ) external view returns (uint256 totalRemaining) {
        for (uint256 i = 0; i < saleIds.length; i++) {
            Sale storage sale = sales[saleIds[i]];
            if (sale.active) {
                totalRemaining += sale.remaining;
            }
        }
    }

    function emergencyWithdraw() external onlyOwner {
        uint256 amount = USDT.balanceOf(address(this));
        USDT.transfer(owner(), amount);
    }
}
