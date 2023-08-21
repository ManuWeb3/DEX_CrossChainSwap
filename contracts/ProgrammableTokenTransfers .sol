// SPDX-License-Identifier: MIT
pragma solidity 0.8.19;

import {IRouterClient} from "@chainlink/contracts-ccip/src/v0.8/ccip/interfaces/IRouterClient.sol";     // router client (Sender)
import {OwnerIsCreator} from "@chainlink/contracts-ccip/src/v0.8/shared/access/OwnerIsCreator.sol";     // onlyOwner modifier
import {Client} from "@chainlink/contracts-ccip/src/v0.8/ccip/libraries/Client.sol";                    // all 3 structs
import {CCIPReceiver} from "@chainlink/contracts-ccip/src/v0.8/ccip/applications/CCIPReceiver.sol";     // NEW - ccipReceiver() (like ccipsend in Router)
import {IERC20} from "@chainlink/contracts-ccip/src/v0.8/vendor/openzeppelin-solidity/v4.8.0/token/ERC20/IERC20.sol";   // CCIP-BnM
import {LinkTokenInterface} from "@chainlink/contracts/src/v0.8/interfaces/LinkTokenInterface.sol";     // to pay fee in LINK (1/2 options)
// built-in by Chainlink already

/**
 * THIS IS AN EXAMPLE CONTRACT THAT USES HARDCODED VALUES FOR CLARITY.
 * THIS IS AN EXAMPLE CONTRACT THAT USES UN-AUDITED CODE.
 * DO NOT USE THIS CODE IN PRODUCTION.
 */

/// @title - A simple messenger contract for transferring/receiving tokens and data across chains.
contract ProgrammableTokenTransfers is CCIPReceiver, OwnerIsCreator {   // "Programmable" due to presence of Receiver contract (coding involved)
    // Custom errors to provide more descriptive revert messages. (require - descriptive cost high gas)
    // only 2 are inherited here
    error NotEnoughBalance(uint256 currentBalance, uint256 calculatedFees); // Used to make sure contract has enough balance to cover the fees.
    error NothingToWithdraw(); // Used when trying to withdraw Ether but there's nothing to withdraw.
    error FailedToWithdrawEth(address owner, address target, uint256 value); // Used when the withdrawal of Ether fails.
    error DestinationChainNotWhitelisted(uint64 destinationChainSelector); // Used when the destination chain has not been whitelisted by the contract owner.
    error SourceChainNotWhitelisted(uint64 sourceChainSelector); // Used when the source chain has not been whitelisted by the contract owner.
    error SenderNotWhitelisted(address sender); // Used when the sender has not been whitelisted by the contract owner.

    // Event emitted when a message is sent to another chain.
    // data types of all the fields are the actual ones commonly used... like address is nnot yet converted to bytes here
    event MessageSent(
        bytes32 indexed messageId, // The unique ID of the CCIP message. - TOO IMPORTANT - indexed
        // message Id available as it is returned by ccipSend()
        uint64 indexed destinationChainSelector, // The chain selector of the destination chain.
        address receiver, // The address of the receiver on the destination chain. (Not indexed)
        string text, // The text being sent.
        address token, // The token address that was transferred.
        uint256 tokenAmount, // The token amount that was transferred.
        address feeToken, // the token address used to pay CCIP fees.
        uint256 fees // The fees paid for sending the message.
        // both detail reg. the fee paid to use CCIP as feePayment is the subject matter of sender here (Not Receiver)
    );

    // Event emitted when a message is received from another chain.
    event MessageReceived(
        bytes32 indexed messageId, // The unique ID of the CCIP message.
        uint64 indexed sourceChainSelector, // The chain selector of the source chain.
        address sender, // The address of the sender from the source chain.
        string text, // The text that was received.
        address token, // The token address that was transferred.
        uint256 tokenAmount // The token amount that was transferred.
        // no detail reg. the fee paid to use CCIP as feePayment is the subject matter of sender here.
    );

    // all 4 private as they store the state, only accessed in getLastReceivedMessageDetails(), _ccipReceive(): BOTH RECEIVE-SPECIFIC FUNCTIONS
    bytes32 private lastReceivedMessageId; // Store the last received messageId. // The Msg contains tokenAmount, tokenAddress, and data (string included)
    address private lastReceivedTokenAddress; // Store the last received token address.
    uint256 private lastReceivedTokenAmount; // Store the last received amount.
    string private lastReceivedText; // Store the last received text.

    // 3 PUBLIC (only read, no state stored) mappings under "Best Practices"

    // 1. Mapping to keep track of whitelisted destination chains.
    mapping(uint64 => bool) public whitelistedDestinationChains;

    // 2. Mapping to keep track of whitelisted source chains.
    mapping(uint64 => bool) public whitelistedSourceChains;

    // 3. Mapping to keep track of whitelisted senders.
    mapping(address => bool) public whitelistedSenders;

    LinkTokenInterface linkToken;

    /// @notice Constructor initializes the contract with the router address.
    /// @param _router The address of the router contract. (on Source B/c). To be further passed to CCIPReceiver.sol
    /// @param _link The address of the link contract. (on Source B/c)
    constructor(address _router, address _link) CCIPReceiver(_router) {
        linkToken = LinkTokenInterface(_link);
    }

    // 3 mappings being checked for whitelist / denylist chain and sender using modifiers

    /// @dev Modifier that checks if the chain with the given destinationChainSelector is whitelisted.
    /// @param _destinationChainSelector The selector of the destination chain.
    modifier onlyWhitelistedDestinationChain(uint64 _destinationChainSelector) {
        if (!whitelistedDestinationChains[_destinationChainSelector])
            revert DestinationChainNotWhitelisted(_destinationChainSelector);
        _;
    }

    /// @dev Modifier that checks if the chain with the given sourceChainSelector is whitelisted.
    /// @param _sourceChainSelector The selector of the destination chain.
    modifier onlyWhitelistedSourceChain(uint64 _sourceChainSelector) {
        if (!whitelistedSourceChains[_sourceChainSelector])
            revert SourceChainNotWhitelisted(_sourceChainSelector);
        _;
    }

    /// @dev Modifier that checks if the chain with the given sourceChainSelector is whitelisted.
    /// @param _sender The address of the sender.
    modifier onlyWhitelistedSenders(address _sender) {
        if (!whitelistedSenders[_sender]) 
            revert SenderNotWhitelisted(_sender);
        _;
    }


    // 6 functions to whitelist and denylist chains and sender using functions, callable by onlyOwner modifier

    /// @dev Whitelists a chain for transactions.
    /// @notice This function can only be called by the owner.
    /// @param _destinationChainSelector The selector of the destination chain to be whitelisted.
    function whitelistDestinationChain(
        uint64 _destinationChainSelector
    ) external onlyOwner {
        whitelistedDestinationChains[_destinationChainSelector] = true;
    }

    /// @dev Denylists a chain for transactions.
    /// @notice This function can only be called by the owner.
    /// @param _destinationChainSelector The selector of the destination chain to be denylisted.
    function denylistDestinationChain(
        uint64 _destinationChainSelector
    ) external onlyOwner {
        whitelistedDestinationChains[_destinationChainSelector] = false;
    }

    /// @dev Whitelists a chain for transactions.
    /// @notice This function can only be called by the owner.
    /// @param _sourceChainSelector The selector of the source chain to be whitelisted.
    function whitelistSourceChain(
        uint64 _sourceChainSelector
    ) external onlyOwner {
        whitelistedSourceChains[_sourceChainSelector] = true;
    }

    /// @dev Denylists a chain for transactions.
    /// @notice This function can only be called by the owner.
    /// @param _sourceChainSelector The selector of the source chain to be denylisted.
    function denylistSourceChain(
        uint64 _sourceChainSelector
    ) external onlyOwner {
        whitelistedSourceChains[_sourceChainSelector] = false;
    }

    /// @dev Whitelists a sender.
    /// @notice This function can only be called by the owner.
    /// @param _sender The address of the sender.
    function whitelistSender(address _sender) external onlyOwner {
        whitelistedSenders[_sender] = true;
    }

    /// @dev Denylists a sender.
    /// @notice This function can only be called by the owner.
    /// @param _sender The address of the sender.
    function denySender(address _sender) external onlyOwner {
        whitelistedSenders[_sender] = false;
    }

    // =============================Cream of the contract begins=================================================================
    // 2 new f() (getLastReceivedMessageDetails, _ccipReceive) to incorporate msg-receive functionality in PTT.sol


    // Full flow @ pg. # 57 in B/c # 12 notebook
    /// @notice Sends data and transfer tokens to receiver on the destination chain.
    /// @notice Pay for fees in LINK.
    /// @dev Assumes your contract has sufficient LINK to pay for CCIP fees. (else fund your contract with LINK prior)
    /// @param _destinationChainSelector The identifier (aka selector) for the destination blockchain.
    /// @param _receiver The address of the recipient on the destination blockchain. (to receive tokens)
    /// @param _text The string data to be sent. (to be processed by _ccipReceive())
    /// @param _token token address.
    /// @param _amount token amount.
    /// @return messageId The ID of the CCIP message that got sent.
    function sendMessagePayLINK(
        uint64 _destinationChainSelector,
        address _receiver,          // converted to bytes using abi.encode(_receiver) inside Client.EVM2AnyMessage struct
        string calldata _text,      // converted to bytes using abi.encode(_text) inside Client.EVM2AnyMessage struct
        address _token,             // to transfer
        uint256 _amount             // amount to transfer
    )
        external
        onlyOwner
        onlyWhitelistedDestinationChain(_destinationChainSelector)      // only 1 check in sending
        returns (bytes32 messageId)
    {
        // Create an EVM2AnyMessage struct in memory with necessary information for sending a cross-chain message
        // address(linkToken) means fees are paid in LINK
        Client.EVM2AnyMessage memory evm2AnyMessage = _buildCCIPMessage(
            _receiver,
            _text,
            _token,
            _amount,
            address(linkToken)
        );

        // Initialize a router client instance to interact with cross-chain router
        IRouterClient router = IRouterClient(this.getRouter());
        
        // Get the fee required to send the CCIP message
        uint256 fees = router.getFee(_destinationChainSelector, evm2AnyMessage);

        if (fees > linkToken.balanceOf(address(this)))
            revert NotEnoughBalance(linkToken.balanceOf(address(this)), fees);

        // approve the Router to transfer LINK tokens on contract's behalf. It will spend the fees in LINK
        linkToken.approve(address(router), fees);

        // approve the Router to spend tokens on contract's behalf. It will spend the amount of the given token
        IERC20(_token).approve(address(router), _amount);

        // Send the message through the router and store the returned message ID - 1st time
        messageId = router.ccipSend(_destinationChainSelector, evm2AnyMessage);

        // Emit an event with message details
        emit MessageSent(       // data in its original type, not enocoded to bytes
            messageId,
            _destinationChainSelector,
            _receiver,
            _text,
            _token,
            _amount,
            address(linkToken),
            fees
        );

        // Return the message ID - 2nd time
        return messageId;
    }

    // Full flow @ pg. # 57 in B/c # 12 notebook
    /// @notice Sends data and transfer tokens to receiver on the destination chain.
    /// @notice Pay for fees in native gas.
    /// @dev Assumes your contract has sufficient native gas like ETH on Ethereum or MATIC on Polygon.
    /// @param _destinationChainSelector The identifier (aka selector) for the destination blockchain.
    /// @param _receiver The address of the recipient on the destination blockchain.
    /// @param _text The string data to be sent.
    /// @param _token token address.
    /// @param _amount token amount.
    /// @return messageId The ID of the CCIP message that got sent.
    
    // receive() external payable {} is used to fund the contract to pay in native.
    function sendMessagePayNative(
        uint64 _destinationChainSelector,
        address _receiver,                 // converted to bytes using abi.encode(_receiver) inside Client.EVM2AnyMessage struct
        string calldata _text,             // converted to bytes using abi.encode(_text) inside Client.EVM2AnyMessage struct
        address _token,                    // to transfer
        uint256 _amount                    // amount to transfer
    )
        external
        onlyOwner
        onlyWhitelistedDestinationChain(_destinationChainSelector)      // only 1 check in sending
        returns (bytes32 messageId)
    {
        // Create an EVM2AnyMessage struct in memory with necessary information for sending a cross-chain message
        // address(0) means fees are paid in native gas
        Client.EVM2AnyMessage memory evm2AnyMessage = _buildCCIPMessage(
            _receiver,
            _text,
            _token,
            _amount,
            address(0)
        );

        // Initialize a router client instance to interact with cross-chain router
        IRouterClient router = IRouterClient(this.getRouter());

        // Get the fee required to send the CCIP message
        uint256 fees = router.getFee(_destinationChainSelector, evm2AnyMessage);

        if (fees > address(this).balance)       // address(this).balance -> native currency balance
            revert NotEnoughBalance(address(this).balance, fees);

        // approve the Router to spend tokens on contract's behalf. It will spend the amount of the given token
        IERC20(_token).approve(address(router), _amount);

        // Send the message through the router and store the returned message ID - 1st time
        messageId = router.ccipSend{value: fees}(           // {value: fees} possible bcz fn() is payable in interface IRC.sol
            _destinationChainSelector,
            evm2AnyMessage
        );

        // Emit an event with message details
        emit MessageSent(           // data in its original type, not enocoded to bytes
            messageId,
            _destinationChainSelector,
            _receiver,
            _text,
            _token,
            _amount,
            address(0),
            fees
        );

        // Return the message ID - 2nd time
        return messageId;
    }

    /**
     * @notice Returns the details of the last CCIP received message.
     * @dev This function retrieves (returns) the ID, text, token address, and token amount of the last received CCIP message.
     * @return messageId The ID of the last received CCIP message.
     * @return text The text of the last received CCIP message.
     * @return tokenAddress The address of the token in the last CCIP received message.
     * @return tokenAmount The amount of the token in the last CCIP received message.
     */
    function getLastReceivedMessageDetails()
        public
        view
        returns (
            bytes32 messageId,
            string memory text,         // data
            address tokenAddress,       // which token
            uint256 tokenAmount         // token amount
        )
    {
        // returns all 4 private state variables declared at the top   
        // all these 4 have been populated in _ccipReceive() below
        return (
            lastReceivedMessageId,
            lastReceivedText,
            lastReceivedTokenAddress,
            lastReceivedTokenAmount
        );
    }

    // complete flow of this function @ B/C note book # 12 @ pg. # 65
    
    /// handle a received message 
    // (Meant for PLUMBING)
    // Extract the details of the last CCIP received message from Client.Any2EVMMessage memory any2EvmMessage and populates (storage-write) the 4 private state vars.
    // Cannot read the 4 state-vars, hence a dedicated getter needed : getLastReceivedMessageDetails()
    function _ccipReceive(
        Client.Any2EVMMessage memory any2EvmMessage         // nowhere constructed by us, gets constructed under the hood, getting this from Client library imported
    )
        internal
        override        // defining its body now, hence overriding
        onlyWhitelistedSourceChain(any2EvmMessage.sourceChainSelector)       // Make sure source chain is whitelisted   // both checks in receive
        onlyWhitelistedSenders(abi.decode(any2EvmMessage.sender, (address))) // Make sure the sender is whitelisted     // both checks in receive
        // both of the above 2 modifiers are added here only => "override" used
        // as none of these is present in the original fn. signature in CCIPREceiver.sol abstract contract
    {
        lastReceivedMessageId = any2EvmMessage.messageId; // fetch the messageId
        lastReceivedText = abi.decode(any2EvmMessage.data, (string)); // abi-decoding of the sent text
        // Expect one token to be transferred at once, but you can transfer several tokens.
        lastReceivedTokenAddress = any2EvmMessage.destTokenAmounts[0].token;
        lastReceivedTokenAmount = any2EvmMessage.destTokenAmounts[0].amount;
        // destTokenAmounts is the name of the array variable that contains, at all of its indices, the elements = each element is again a struct i.e. EVMTokenAmount
        // destTokenAmounts[0] = destToken -> is a variable of struct type - EVMTokenAmount

        // MVP logic: fetch, store, and emit
        emit MessageReceived(
            any2EvmMessage.messageId,           // lastReceivedMessageId
            any2EvmMessage.sourceChainSelector, // fetch the source chain identifier (aka selector)
            abi.decode(any2EvmMessage.sender, (address)),   // abi-decoding of the sender address,
            abi.decode(any2EvmMessage.data, (string)),      // lastReceivedText
            any2EvmMessage.destTokenAmounts[0].token,       // lastReceivedTokenAddress
            any2EvmMessage.destTokenAmounts[0].amount       // lastReceivedTokenAmount
        );
    }

    /// @notice Construct a CCIP message. // and step by step input all the params in the Client.EVM2AnyMessage struct
    /// @dev This function will create an EVM2AnyMessage struct with all the necessary information for programmable tokens transfer.
    /// @param _receiver The address of the receiver.
    /// @param _text The string data to be sent.
    /// @param _token The token to be transferred.
    /// @param _amount The amount of the token to be transferred.
    /// @param _feeTokenAddress The address of the token used for fees. Set address(0) for native gas.
    /// @return Client.EVM2AnyMessage Returns an EVM2AnyMessage struct which contains information (to build and) for sending a CCIP message.
    function _buildCCIPMessage(
        address _receiver,
        string calldata _text,
        address _token,
        uint256 _amount,
        address _feeTokenAddress
    ) internal pure returns (Client.EVM2AnyMessage memory) {        // internal: called by sendMessagePayNative / sendMessagePayToken (Link for now)
        // Set the token amounts. Step # 1
        Client.EVMTokenAmount[]                                     // creating array of struct - new. memory's there due to struct
            memory tokenAmounts = new Client.EVMTokenAmount[](1);
        Client.EVMTokenAmount memory tokenAmount = Client.EVMTokenAmount({      // no new keyword for array's element. memory's there due to struct
            token: _token,
            amount: _amount
        });
        tokenAmounts[0] = tokenAmount;
        // Create an EVM2AnyMessage struct in memory with necessary information for sending a cross-chain message. Step # 2
        Client.EVM2AnyMessage memory evm2AnyMessage = Client.EVM2AnyMessage({   // no array of messages, hence no array-element. just a struct-variable. NO to new, YES to memory
            receiver: abi.encode(_receiver), // ABI-encoded receiver address - bcz msg can only read / send bytes
            data: abi.encode(_text), // ABI-encoded string
            tokenAmounts: tokenAmounts, // The amount and type of token being transferred
            extraArgs: Client._argsToBytes(
                // Additional arguments, setting gas limit and non-strict sequencing mode
                Client.EVMExtraArgsV1({gasLimit: 200_000, strict: false})       // 200_000: bcz sending data that ccipReceive() will run a code to process the data, hence gas.
            ),
            // Set the feeToken to a feeTokenAddress, indicating specific asset will be used for fees
            feeToken: _feeTokenAddress
        });
        // Step # 3
        return evm2AnyMessage;
    }

    /// @notice Fallback function to allow the contract to receive Ether.
    /// @dev This function has no function body, making it a default function for receiving Ether.
    /// It is automatically called when Ether is sent to the contract without any data. - to fund the contract for paying in native currency
    receive() external payable {}

    /// @notice Allows the contract owner to withdraw the entire balance of Ether from the contract.
    /// @dev This function reverts if there are no funds to withdraw or if the transfer fails.
    /// It should only be callable by the owner of the contract.
    /// @param _beneficiary The address to which the Ether should be sent.
    function withdraw(address _beneficiary) public onlyOwner {
        // Retrieve the balance of this contract
        uint256 amount = address(this).balance;

        // Revert if there is nothing to withdraw
        if (amount == 0) revert NothingToWithdraw();

        // Attempt to send the funds, capturing the success status and discarding any return data
        // address.call{value: ETHamount}
        (bool sent, ) = _beneficiary.call{value: amount}("");

        // Revert if the send failed, with information about the attempted transfer
        if (!sent) revert FailedToWithdrawEth(msg.sender, _beneficiary, amount);
    }

    /// @notice Allows the owner of the contract to withdraw all tokens of a specific ERC20 token.
    /// @dev This function reverts with a 'NothingToWithdraw' error if there are no tokens to withdraw.
    /// @param _beneficiary The address to which the tokens will be sent.
    /// @param _token The contract address of the ERC20 token to be withdrawn.
    function withdrawToken(
        address _beneficiary,
        address _token          
    ) public onlyOwner {
        // Retrieve the balance of this contract
        uint256 amount = IERC20(_token).balanceOf(address(this));   // enough to invoke the ERC20 function, as it's nothing but the object itself

        // Revert if there is nothing to withdraw
        if (amount == 0) revert NothingToWithdraw();

        IERC20(_token).transfer(_beneficiary, amount);
        // token.transfer()
    }
}