pragma solidity >=0.4.22 <0.7.0;

/**
 * A two player game of Morra on Ethereum.
 * https://en.wikipedia.org/wiki/Morra_(game)
 */
contract MorraGame {
    // represents a player object
    struct Player {
        address payable addr; // player address must be payable to receive ETH
        bytes32 hash;
        // packed uint8 in struct saves storage
        // https://ethereum.stackexchange.com/a/3111
        uint8 pick;
        uint8 guess;
    }

    event PreviousGameTimedOut();

    address payable nullAddress = address(0);
    Player noPlayer = Player(nullAddress, 0, 0, 0);
    // timer for deadlocks, timeout = 30 minutes
    uint256 timer;

    Player private player1;
    Player private player2;
    mapping(address => uint256) private playerBalances;

    /**
     * Play function. Send your hashed input along with 5 ETH to cast your numbers.
     */
    function play(bytes32 hash) public payable {
        require(msg.value == 5 ether, "5 ETH required.");
        // add this bet to the player's balance
        playerBalances[msg.sender] += msg.value;

        if (isGameStale()) {
            // previous game is stale, end in a "draw" and start a new one
            timer = 0;
            emit PreviousGameTimedOut();
            // give a player who revealed their numbers 3 ETH from the other player's buy-in
            uint256 penalty = 3 ether;
            if (player1.pick != 0) {
                playerBalances[player2.addr] -= penalty;
                playerBalances[player1.addr] += penalty;
            }
            if (player2.pick != 0) {
                playerBalances[player1.addr] -= penalty;
                playerBalances[player2.addr] += penalty;
            }
            reset();
        }

        // make the player, necessary regardless of operation
        Player memory newPlayer = Player(msg.sender, hash, 0, 0); // pick, guess not yet initialized

        if (player1.addr == nullAddress) {
            // player 1 has not played yet
            player1 = newPlayer;
        } else {
            require(
                player1.addr != newPlayer.addr,
                "Already playing, try again later!"
            );
            // player 2 activates the game
            player2 = newPlayer;
            // start the timeout timer after two players have committed
            timer = now;
        }
    }

    /**
     * Reveal function. Send your plaintext inputs to be verified against the hash.
     */
    function reveal(
        uint8 pick,
        uint8 guess,
        uint256 salt
    ) public {
        // players have played
        require(
            player1.addr != nullAddress && player2.addr != nullAddress,
            "Cannot reveal yet!"
        );
        // reveal must come from a player
        require(
            msg.sender == player1.addr || msg.sender == player2.addr,
            "You are not playing!"
        );
        // numbers must be between 1 and 5, refuse to progress otherwise
        require(
            pick >= 1 && pick <= 5 && guess >= 1 && guess <= 5,
            "You must choose numbers between 1 and 5."
        );

        bytes32 calcd = gameHash(pick, guess, salt);
        string memory badhashMsg = "Bad hash, try again!";
        // either player can reveal first
        if (msg.sender == player1.addr) {
            require(calcd == player1.hash, badhashMsg);
            player1.pick = pick;
            player1.guess = guess;
        } else if (msg.sender == player2.addr) {
            require(calcd == player2.hash, badhashMsg);
            player2.pick = pick;
            player2.guess = guess;
        }
        // hashes revealed and matched, do the game
        if (player1.pick != 0 && player2.pick != 0) {
            // calculate reward based on sum of picks
            uint256 reward = ((player1.pick + player2.pick) * 1 ether) / 2;

            // update the respective player balances
            if (player1.guess == player2.pick) {
                // hand limit over to player 1
                playerBalances[player2.addr] -= reward;
                playerBalances[player1.addr] += reward;
            }
            if (player2.guess == player1.pick) {
                // hand limit over to player 2
                playerBalances[player1.addr] -= reward;
                playerBalances[player2.addr] += reward;
            }
            reset();
        }
    }

    function reset() private {
        player1 = noPlayer;
        player2 = noPlayer;
    }

    function bail() public {
        require(
            msg.sender == player1.addr && player2.addr == nullAddress,
            "Committed, can't bail."
        );
        // player1 wants to bail, no player2, stop this game
        reset();
    }

    function withdrawBalance() public {
        require(
            !(player1.addr == msg.sender || player2.addr == msg.sender),
            "Can't withdraw during a game!"
        );
        uint256 e = playerBalances[msg.sender];
        if (e > 0) {
            // prevent re-entrancy
            playerBalances[msg.sender] = 0;
            msg.sender.transfer(e);
        }
    }

    function viewBalance() public view returns (uint256) {
        return playerBalances[msg.sender];
    }

    function gameHash(
        uint8 pick,
        uint8 guess,
        uint256 salt
    ) public pure returns (bytes32) {
        // keccak256(abi.encodePacked(a, b)) is a way to compute the hash of structured data
        // (although be aware that it is possible to craft a “hash collision” using different function parameter types).
        // https://solidity.readthedocs.io/en/v0.6.6/units-and-global-variables.html
        return keccak256(abi.encode(pick, guess, salt));
    }

    /**
     * Function to view if the current game is stale and can be terminated.
     */
    function isGameStale() public view returns (bool) {
        return timer != 0 && (now - timer) >= 30 minutes;
    }

    function safeToReveal() public view returns (bool) {
        return
            (player1.addr != nullAddress && player2.addr != nullAddress) &&
            (player1.hash != 0 && player2.hash != 0);
    }
}
