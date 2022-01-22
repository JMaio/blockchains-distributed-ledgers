// SPDX-License-Identifier: UNLICENSED

pragma solidity >=0.7.0 <0.8.0;

// import './SafeMath.sol';

interface CustomToken {
    function transfer(address recipient, uint256 amount) external;

    function getBalance() external returns (uint256);
}

struct PartyTerms {
    // if a contract is defined (not "0") the terms have been set
    // (https://stackoverflow.com/a/48220805/9184658)
    // don't declare this address as a CustomToken contract,
    // it cannot be verified anyway...
    address sourceContract;
    uint256 tokensToSwap;
}

// steps:
// A / B creates swap, stating other's address
// state terms
// other user confirms
// each transfer the required tokens and "lock"
//   -- locking can only happen if the correct number of tokens is supplied
// before both lock, they can bail
// once both lock, no going back
// can now "complete", asking the contract to transfer tokens to them in the other contract

// create / confirm used as extra verification

contract FairSwap {
    // using SafeMath for uint;

    address public owner;
    uint256 public collateralETH;
    uint256 public swapStartTime;

    address payable a;
    address payable b;

    event SwapStarted(address a, address b);
    event TermsSet(address party, address tokenContract, uint256 amount);
    event TermsAccepted(address party);
    event DepositConfirmed(address party);
    event Executed(address party);
    event Cancelled(address party);
    event SwapComplete();

    // re-usable mapping for keeping state
    mapping(address => bool) stageCompleted;

    // store party terms. party A proposes terms to B,
    // and what they are to receive is stored under their address
    mapping(address => PartyTerms) partyTerms;

    // https://docs.soliditylang.org/en/v0.8.0/common-patterns.html#state-machine
    enum Stages {
        ReadyToStart,
        SwapStarted,
        TermsSet,
        TermsAccepted,
        DepositConfirmed,
        Executed
        // cancelled, wait for refunds
        // Cancelled
    }
    // This is the current stage.
    Stages public stage = Stages.ReadyToStart;

    // go to next stage and reset stage state
    function nextStage() internal {
        stage = Stages(uint256(stage) + 1);
    }

    function setStageCompleteAndProgress(address w) internal {
        stageCompleted[w] = true;
        address o = getOtherParty(w);
        if (stageCompleted[o]) {
            // both parties completed
            stageCompleted[w] = false;
            stageCompleted[o] = false;
            // progress
            nextStage();
        }
    }

    modifier onlyParty() {
        require(
            msg.sender == a || msg.sender == b,
            "Must be a swap party to do this"
        );
        _;
    }

    modifier onlyOwner() {
        require(msg.sender == owner, "Only owner can do this");
        _;
    }

    // https://docs.soliditylang.org/en/v0.8.0/common-patterns.html
    modifier onlyAfter(uint256 _time) {
        require(block.timestamp >= _time, "Function called too early");
        _;
    }

    modifier atStage(Stages _stage) {
        require(stage == _stage, "Function cannot be called at this time");
        _;
    }

    modifier beforeStage(Stages _stage) {
        require(stage < _stage, "Function cannot be called at this time");
        _;
    }

    constructor() {
        owner = msg.sender;
    }

    // ===============================================================
    //  swap setup (create, set terms)
    // ===============================================================

    /**
     * a single user sets up a minimal swap by providing the address of the other party
     */
    function step0_createSwap(
        address payable otherParty,
        uint256 _collateralETH
    ) public atStage(Stages.ReadyToStart) {
        require(msg.sender != otherParty, "Party addresses cannot be equal");
        // record the swap parties' addresses
        a = msg.sender;
        b = otherParty;

        // collateral set by the user who creates the swap
        collateralETH = _collateralETH;

        // reset swap start time
        swapStartTime = block.timestamp;

        // only called by a single user
        nextStage();

        emit SwapStarted(msg.sender, otherParty);
    }

    /**
     * each user should set their own swap terms for gas fairness
     */
    function step1_setSwapTerms(address sourceContract, uint256 amount)
        public
        atStage(Stages.SwapStarted)
    {
        // cannot use "0" address
        // https://stackoverflow.com/a/48220805/9184658
        // require(
        //     sourceContract != address(0),
        //     "Source contract cannot be 0x0"
        // );
        // can only be set once, not modified afterwards
        require(
            partyTerms[msg.sender].sourceContract == address(0),
            "Cannot change swap terms: cancel if necessary"
        );

        // record the terms set by this party
        partyTerms[msg.sender] = PartyTerms(sourceContract, amount);

        setStageCompleteAndProgress(msg.sender);

        emit TermsSet(msg.sender, sourceContract, amount);
    }

    /**
     * "view" allowing each party to review the terms of the swap prior to accepting
     */
    function reviewTerms()
        public
        view
        returns (
            address party1,
            address contract1,
            uint256 party1_Tokens,
            address party2,
            address contract2,
            uint256 party2_Tokens
        )
    {
        PartyTerms memory ptA = partyTerms[a];
        PartyTerms memory ptB = partyTerms[b];
        return (
            a,
            ptA.sourceContract,
            ptA.tokensToSwap,
            b,
            ptB.sourceContract,
            ptB.tokensToSwap
        );
    }

    /**
     * each user should check, and then accept the terms.
     * users must also provide the correct amount of collateral set at the beginning
     */
    function step2_acceptTerms()
        public
        payable
        onlyParty
        atStage(Stages.TermsSet)
    {
        // store collateral
        require(msg.value == collateralETH, "Must provide agreed collateral");

        // terms have been accepted by the sender, this stage is confirmed by this user
        setStageCompleteAndProgress(msg.sender);

        emit TermsAccepted(msg.sender);
    }

    // ===============================================================
    //  deposit checking
    // ===============================================================

    // after accepting terms, both users should "transfer" to the contract
    // store the number of tokens deposited?
    /**
     * "confirm" that you have transferred the required tokens to the contract
     */
    function step3_confirmDeposit()
        public
        onlyParty
        atStage(Stages.TermsAccepted)
    {
        // check balance on this user's contract
        PartyTerms memory pt = partyTerms[msg.sender];
        CustomToken sourceContract = CustomToken(pt.sourceContract);

        uint256 balance = sourceContract.getBalance();
        // since there is only ever one swap happening, we should
        // only have exactly the required amount of tokens
        // --> **assume that users only transfer either the exact number of tokens required, or none at all**
        if (balance < pt.tokensToSwap) {
            revert("Incorrect number of tokens provided");
        } else if (balance > pt.tokensToSwap) {
            // balance higher than expected, return the difference
            sourceContract.transfer(msg.sender, balance - pt.tokensToSwap);
        }
        // should now be equal
        // require(
        //     balance == pt.tokensToSwap,
        //     "Incorrect number of tokens provided"
        // );

        // // take this opportunity to return the tokens if amount not correct
        // uint256 tokenBalance = sourceContract.getBalance();
        // if (tokenBalance != pt.tokensToSwap) {
        //     sourceContract.transfer(msg.sender, tokenBalance - pt.tokensToSwap);
        //     revert("Incorrect number of tokens provided: refund issued");
        // }

        // then this deposit is confirmed
        // if any more tokens are added after this, we are not responsible
        setStageCompleteAndProgress(msg.sender);

        emit DepositConfirmed(msg.sender);
    }

    // ===============================================================
    //  swap execution
    // ===============================================================

    function step4_requestFinalTransfer()
        public
        onlyParty
        atStage(Stages.DepositConfirmed)
    {
        // the contract is in the possession of all tokens, so pass them to their new owners
        // can only be called once
        require(
            !stageCompleted[msg.sender],
            "Swapped tokens already transferred"
        );

        address o = getOtherParty(msg.sender);

        PartyTerms memory targetTerms = partyTerms[o];
        CustomToken sourceContract = CustomToken(targetTerms.sourceContract);

        // prevent re-entrancy
        setStageCompleteAndProgress(msg.sender);

        // transfer tokens in the new contract
        sourceContract.transfer(msg.sender, targetTerms.tokensToSwap);
        // return collateral
        payable(msg.sender).transfer(collateralETH);

        emit Executed(msg.sender);

        // reset other party's terms since this user is no longer owed anything
        reset(o);

        if (stage == Stages.Executed) {
            // both parties have requested, swap complete
            // a = address(0);
            // b = address(0);
            stage = Stages.ReadyToStart;
            emit SwapComplete();
        }
    }

    // ===============================================================
    //  swap cancelled / ends
    // ===============================================================

    /**
     * if either party cancels the swap, they should both be allowed to claim what they had transferred
     * can't give a penalty because we don't know why the user has cancelled.
     * It could be that user A has completed their deposit, but B hasn't, or a user willingly cancels
     * at the last minute because they do not agree to the terms.
     * The user who cancels must wait at least one hour (or n hours), which would give a
     * legitimate user enough time to transfer and confirm their deposit.
     * Depends on deposits:
     * - If A has deposited, but not B, A can cancel because B bailed.
     * - If A has completed the stage, B cannot cancel. But A can cancel.
     * - If neither A or B have deposited, either can cancel but both were bad for not depositing
     * - If both have deposited (but one or both not confirmed), either can cancel and ???
     */
    function cancel()
        public
        onlyParty
        onlyAfter(swapStartTime + 6 hours)
        beforeStage(Stages.DepositConfirmed)
    {
        // cannot cancel once both deposits have been confirmed
        // if TermsAccepted stage is reached, there should be a penalty for not swapping
        address o = getOtherParty(msg.sender);

        // if you have accepted terms, then you may get collateral when the other cancels,
        // but you must be in this stage, since the next stage is when deposits are confirmed
        // and the swap can no longer be cancelled
        if (stage == Stages.TermsAccepted) {
            // collateral has been paid in,
            // you can only cancel after agreeing terms if the other person has not already completed the step
            require(
                !stageCompleted[o],
                "Other party has already completed this step, you cannot cancel"
            );
            // that is the case, so you'll receive your collateral
            // https://ethereum.stackexchange.com/a/35412
            // > If the only maths you need to do is adding sums of Ether obtained from msg.value to other
            // > sums of Ether obtained from msg.value, it shouldn't be necessary to use SafeMath, since
            // > the msg.value is bounded by the number of Ether in existence, which is well below the
            // > range that can be represented by a uint256.
            payable(msg.sender).transfer(collateralETH);

            if (stageCompleted[msg.sender]) {
                // additionally, if you've completed the stage, you'll be refunded
                // your tokens and *all* the collateral
                payable(msg.sender).transfer(collateralETH);
                PartyTerms memory pt = partyTerms[msg.sender];
                CustomToken(pt.sourceContract).transfer(
                    msg.sender,
                    pt.tokensToSwap
                );
            } else {
                // if not, the other person gets their share of the collateral
                payable(o).transfer(collateralETH);
            }
        }

        reset(msg.sender);
        reset(o);

        // otherwise, just cancel, nothing lost
        stage = Stages.ReadyToStart;

        emit Cancelled(msg.sender);
    }

    // ===============================================================
    //  utility functions
    // ===============================================================

    function getOtherParty(address w) public view returns (address payable) {
        address payable otherParty;
        if (w == a) {
            otherParty = b;
        } else if (w == b) {
            otherParty = a;
        }
        // returns address(0) if not a party?
        return otherParty;
    }

    // can only call manual override 6 hours after "cancel" becomes avilable
    function manualOverride()
        public
        onlyOwner
        onlyAfter(swapStartTime + 12 hours)
        beforeStage(Stages.Executed)
    {
        // owner returns collateral, tokens, etc
    }

    function reset(address o) internal {
        // reset other party's terms since the party requesting reset is no longer owed anything
        partyTerms[o] = PartyTerms(address(0), 0);
    }
}
