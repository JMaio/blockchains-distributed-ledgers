// SPDX-License-Identifier: UNLICENSED

pragma solidity >=0.7.0 <0.8.0;

// // using solidity 0.8.0 removes the need for SafeMath

// define the SafeMath interface
interface SafeMath {
    function add(uint256 a, uint256 b) external pure returns (uint256);

    function sub(uint256 a, uint256 b) external pure returns (uint256);

    function mul(uint256 a, uint256 b) external pure returns (uint256);

    function div(uint256 a, uint256 b) external pure returns (uint256);

    function mod(uint256 a, uint256 b) external pure returns (uint256);
}

/**
 * Custom Token implementation
 * note: debug messages in `require` calls could be omitted, but
 *       are kept for clarity even if their storage uses more gas
 */
contract CustomToken {
    // https://ethereum.stackexchange.com/a/72962
    // point to a deployed instance of SafeMath
    SafeMath ExternalSafeMath;

    /** Token price in wei */
    uint256 public tokenPrice;

    // Contract deployer and owner
    address private owner;

    // Track number of tokens issued for price change calculations
    uint256 private tokensIssued = 0;
    // Track amount of ETH "floating" in the market; corresponds to the
    //  contract's balance if not using a "withdrawal" system
    uint256 private floatETH = 0;

    // Store token balance for each address */
    mapping(address => uint256) private tokenBalance;

    // Store  ETH  balance for each address (withdrawal-type system) */
    // mapping(address => uint256) private ethBalance;

    event Purchase(address buyer, uint256 amount);
    event Transfer(address sender, address receiver, uint256 amount);
    event Sell(address seller, uint256 amount);
    event Price(uint256 price);

    modifier onlyOwner() {
        require(msg.sender == owner, "Only owner can do this");
        _;
    }

    /**
     * checks whether the user owns at least `amount` tokens
     */
    modifier requireTokens(uint256 amount) {
        require(tokenBalance[msg.sender] >= amount, "Not enough tokens owned");
        _;
    }

    /**
     * @param startingPrice The initial token price in wei
     */
    constructor(uint256 startingPrice, SafeMath safeMath) {
        owner = msg.sender;
        // owner defines starting token price as no tokens have been issued yet
        // this could be zero so it's not enforced. this code enforces a minimum
        // require(
        //     startingPrice > 0,
        //     "Token starting price cannot be zero"
        // );
        tokenPrice = startingPrice;
        ExternalSafeMath = SafeMath(safeMath);
    }

    // ===============================================================
    //  public API
    // ===============================================================

    /**
     * a function via which a user purchases `amount` number of tokens by paying
     * the equivalent price in wei; if the purchase is successful, the function
     * returns a boolean value (true) and emits an event Purchase with the
     * buyer's address and the purchased amount
     * @param amount The number of tokens to purchase
     */
    function buyToken(uint256 amount) public payable returns (bool) {
        // uint256 value = amount * tokenPrice;
        uint256 value = calcPrice(amount);
        require(msg.value == value, "Incorrect ETH / token amount");

        // tokenBalance[msg.sender] += amount;
        // tokensIssued += amount;
        tokenBalance[msg.sender] = ExternalSafeMath.add(
            tokenBalance[msg.sender],
            amount
        );
        tokensIssued = ExternalSafeMath.add(tokensIssued, amount);

        // this eth is now is the contract's possession
        // floatETH += value;
        floatETH = ExternalSafeMath.add(floatETH, value);

        emit Purchase(msg.sender, amount);
        return true;
    }

    /**
     * a function that transfers amount number of tokens from the account of
     * the transaction's sender to the recipient; if the transfer is successful,
     * the function returns a boolean value (true) and emits an event Transfer,
     * with the sender's and receiver's addresses and the transferred amount
     *
     * >> Note: it's possible to transfer your own tokens to yourself.
     *          *Why* you would want to do that is a different question.
     */
    function transfer(address recipient, uint256 amount)
        public
        requireTokens(amount)
        returns (bool)
    {
        // tokenBalance[msg.sender] -= amount;
        // tokenBalance[recipient ] += amount;
        tokenBalance[msg.sender] = ExternalSafeMath.sub(
            tokenBalance[msg.sender],
            amount
        );
        tokenBalance[recipient] = ExternalSafeMath.add(
            tokenBalance[recipient],
            amount
        );

        emit Transfer(msg.sender, recipient, amount);
        return true;
    }

    /**
     * a function via which a user sells amount number of tokens and receives
     * from the contract tokenPrice wei for each sold token; if the sell is
     * successful, the sold tokens are destroyed, the function returns a boolean
     * value (true) and emits an event Sell with the seller's address and the
     * sold amount of tokens
     */
    function sellToken(uint256 amount)
        public
        requireTokens(amount)
        returns (bool)
    {
        // tokenBalance[msg.sender] -= amount;
        // tokensIssued -= amount;
        tokenBalance[msg.sender] = ExternalSafeMath.sub(
            tokenBalance[msg.sender],
            amount
        );
        tokensIssued = ExternalSafeMath.sub(tokensIssued, amount);

        // uint256 value = amount * tokenPrice;
        uint256 value = calcPrice(amount);

        // this eth is *no longer* is the contract's possession
        // floatETH -= value;
        floatETH = ExternalSafeMath.sub(floatETH, value);

        // ethBalance[msg.sender] += value;
        // ethBalance[msg.sender] = ExternalSafeMath.add(ethBalance[msg.sender], value);
        // "transfer" uses the remaining gas to execute the transfer
        payable(msg.sender).transfer(value);

        emit Sell(msg.sender, amount);
        return true;
    }

    /**
     * a function via which the contract's creator can change the tokenPrice;
     * if the action is successful, the function returns a boolean value (true)
     * and emits an event Price with the new price
     */
    function changePrice(uint256 price) public onlyOwner {
        // check that the contract's funds suffice so that all
        // tokens can be sold for the updated price
        // https://ethereum.stackexchange.com/a/21449
        // tokensIssued * price <= address(this).balance,
        require(
            // tokensIssued * price <= floatETH,
            ExternalSafeMath.mul(tokensIssued, price) <= floatETH,
            "Not enough funds to cover price increase"
        );

        tokenPrice = price;
        emit Price(price);
    }

    /**
     * a view that returns the amount of tokens that the user owns
     * @return Returns the number of tokens that the user owns
     */
    function getBalance() public view returns (uint256) {
        return tokenBalance[msg.sender];
    }

    // // ===============================================================
    // //  utility functions
    // // ===============================================================

    /**
     * a view to calculate the price to pay for buying `amount` tokens
     * at the current token price
     */
    function calcPrice(uint256 amount) internal view returns (uint256) {
        // return amount * tokenPrice;
        return ExternalSafeMath.mul(amount, tokenPrice);
    }

    // /**
    //  * @return Returns the user's ETH balance
    //  */
    // function getETHBalance() public view returns (uint256) {
    //     return ethBalance[msg.sender];
    // }

    // /**
    //  * allows a user to withdraw their ETH balance in the contract
    //  * (after selling their tokens)
    //  */
    // function withdrawETHBalance() public {
    //     // https://docs.soliditylang.org/en/v0.8.0/solidity-by-example.html#id2
    //     // "Blind auction" contains withdrawal system
    //     uint256 e = ethBalance[msg.sender];
    //     if (e > 0) {
    //         // It is important to set this to zero because the recipient
    //         // can call this function again as part of the receiving call
    //         // before `send` returns.
    //         ethBalance[msg.sender] = 0;
    //         payable(msg.sender).transfer(e);
    //     }
    // }

    // // ===============================================================
    // //  debug - only owner
    // // ===============================================================

    // function viewContractBalance() public view onlyOwner returns (uint256) {
    //     return address(this).balance;
    // }

    // function viewProfit() public view onlyOwner returns (uint256) {
    //     // return floatETH - (tokensIssued * tokenPrice);
    //     return ExternalSafeMath.sub(floatETH, ExternalSafeMath.mul(tokensIssued, tokenPrice));
    // }

    // /**
    //  * destroy the contract
    //  * https://medium.com/better-programming/solidity-what-happens-with-selfdestruct-f337fcaa58a7
    //  *
    //  * https://ethereum.stackexchange.com/a/347
    //  *  > For example, calling `selfdestruct(address)` sends
    //  *  > all of the contract's current balance to `address`.
    //  */
    // function close() public onlyOwner {
    //     selfdestruct(payable(owner));
    // }
}
