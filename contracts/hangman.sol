// SPDX-License-Identifier: BSD-3-Clause-Clear

pragma solidity >=0.8.13 <=0.8.20;

import "fhevm/lib/TFHE.sol";

contract HangmanFactory {
    event GameCreated(address indexed player, address gameContract);

    address public master;
    euint32[] private fourBytes;
    uint256 public currentWord;

    constructor (address _master) {
        master = _master;
    }

    function getWordsTotal() public view returns(uint256) {
        return fourBytes.length;
    }

    function addWord(bytes memory inSecret) public onlyMaster {
        fourBytes.push(TFHE.asEuint32(inSecret));
    }

    function CreateGame(address player) public returns (address) {
        HangmanGame game = new HangmanGame(player, currentWord);
        if (currentWord < fourBytes.length) {
            game.setWord(fourBytes[currentWord]);
        } else {
            game.setWord(fourBytes[0]);
        }
        currentWord++;
        emit GameCreated(player, address(game));
        return address(game);
    }

    modifier onlyMaster() {
        require(msg.sender == master);
        _;
    }
}

contract HangmanGame {
    euint8[4] private encryptedCharsInv;
    bytes private decryptedWord;

    bool private luckyGuess;
    bool private playerWon;
    uint8 private lives;
    uint8 private nOfCellsRevealed;

    uint8 private constant MAX_LETTERS = 4;
    uint8 private constant QUESTIONMARK = 63;
    uint8 private constant UNDERSCORE = 95;

    bytes private wrongGuesses;
    address private factory;

    address public player;
    uint256 public gameID;

    event GuessedCorrectly(string indexed letter);
    event GuessedIncorrectly(string indexed letter);

    constructor (address _player, uint256 _gameID) {
        lives = 11;
        factory = msg.sender;
        player = _player;
        gameID = _gameID;
    }

    function setWord(euint32 fourBytes) public onlyFactory {
        decryptedWord = new bytes(MAX_LETTERS);

        for (uint8 i = 0; i < MAX_LETTERS; i++){
            euint8 letter = TFHE.asEuint8(TFHE.shr(fourBytes, i*8));
            //Make sure the letter is a valid a-z-A-Z character
            ebool isLetter = TFHE.asEbool(TFHE.and(TFHE.asEuint8(TFHE.ge(letter, 65)), TFHE.asEuint8(TFHE.le(letter, 122))));
            //If not uppercase -> make it uppercase
            ebool isUpperCase = TFHE.asEbool(TFHE.and(TFHE.asEuint8(TFHE.ge(letter, 65)), TFHE.asEuint8(TFHE.le(letter, 90))));
            euint8 uppercaseLetter = TFHE.cmux(isUpperCase, letter, TFHE.sub(letter, 32));

            TFHE.optReq(isLetter);
            
            //encryptedCharsInv.push(uppercaseLetter);
            encryptedCharsInv[i] = uppercaseLetter;
            decryptedWord[i] = bytes1(uint8(UNDERSCORE));
        }
    }

    function guessLetter(string memory letter) public onlyPlayer {
        require(lives > 0);

        bool foundAtLeastOne = false;
        bytes memory asBytes = bytes(letter);
        uint8 firstByte = uint8(asBytes[0]);

        //Make sure the letter is a valid a-z-A-Z character
        bool ifValidLetter = firstByte >= 65 && firstByte <= 122;
        require(ifValidLetter);

        //If not uppercase -> make it uppercase
        bool ifUpperCase = firstByte >= 65 && firstByte <= 90;
        firstByte = ifUpperCase ? firstByte : firstByte - 32;

        for (uint8 i = 0; i < encryptedCharsInv.length; i++) {
            ebool possibleMatch = TFHE.eq(encryptedCharsInv[i] , firstByte);
            if (TFHE.decrypt(possibleMatch) == true) {
                uint8 decryptedLetter = TFHE.decrypt(encryptedCharsInv[i]);
                decryptedWord[decryptedWord.length-1 - i] = bytes1(decryptedLetter);
                foundAtLeastOne = true;
                nOfCellsRevealed = nOfCellsRevealed + 1;
            }
        }

        if (foundAtLeastOne) {
            if (nOfCellsRevealed >= encryptedCharsInv.length) {
                setPlayerAsWinner();
            }
            emit GuessedCorrectly(letter);
        } else {
            lives = lives - 1;
            wrongGuesses = bytes.concat(wrongGuesses, bytes1(firstByte));
            emit GuessedIncorrectly(letter);
        }
    }

    function setPlayerAsWinner() internal {
        playerWon = true;
    }

    function guessEntireWord(string memory word) public onlyPlayer {
        require(lives > 0);
        require(bytes(word).length == encryptedCharsInv.length);

        bytes memory asBytes = bytes(word);
        for (uint8 i = 0; i < encryptedCharsInv.length; i++) {
            ebool possibleMatch = TFHE.eq(encryptedCharsInv[i] , uint8(asBytes[bytes(word).length-1 - i]));
            if (TFHE.decrypt(possibleMatch) == false) {
                //Guessed incorrectly, game over
                lives = 0;
            } else {
                //Guessed correctly
                luckyGuess = true;
                setPlayerAsWinner();
            }
        }
    }

    function showWord() public view returns (string memory) {
        return string(decryptedWord);
    }

    function showMisses() public view returns (string memory) {
        return string(wrongGuesses);
    }

    function hasWon() public view returns (bool) {
        return playerWon;
    }

    modifier onlyFactory() {
        require(msg.sender == factory);
        _;
    }

    modifier onlyPlayer() {
        require(msg.sender == player);
        _;
    }
}