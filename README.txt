**An MVP Cross-chain DEX that is used to swap TGOLD ERC-20 tokens to CCIP-BnM token between Ethereum Sepolia and Polygon Mumbai blockchains.**

Execution: It's pretty simple and fast to spin up and run on RemixIDE.

Open https://remix.ethereum.org/
Activate DGIT extension
Clone this public repo: https://github.com/ManuWeb3/DEX_CrossChainSwap.git
Update the Remix Compiler version to minimum of 0.8.4 (^0.8.4)
Switch the environment to "Injected Metamask provider - Sepolia"
Compile and Deploy the contract.

Will soon paste the Contracts' control flow in a diagram / flowchart to understand the workflow.

**Steps to execute locally:**
1. Deploy TGOLD.sol and DummyCCIP_BnM.sol on Sepolia
2. You should have received 10 full tokens of each of these ERC-20 contracts in your deployer account on Sepolia.
3. Switch to Mumbai in Metamask, to deploy 3 contracts
4. Deploy DummyCCIP_BnMMumbai.sol ERC-20 token on Mumbai and wallet will get 10 full tokens for this as well.
5. Deploy RxExchangeMumbai.sol
6. Deploy CCIPDestContract.sol. Its constructor takes the router's and RxExchangeMumbai's address as inputs at deployment.
7. Set the address of CCIPDestContract.sol in RxExchangeMumbai.sol using setDestContract()
8. Switch back to Sepolia n/w in Metamask.
9. And, finally, deploy SenderExchange.sol with all the input addresses that its constructor initializes it with.
10. Approve SenderExchange.sol as spender for both of the ERC20 token contracts: TGOLD.sol and DummyCCIP_BnM tokens
11. The, execute addLiquidity(). Wait for CCIP message to be successfully sent over to Mumbai from Sepolia which will add an equal amount of DummyCCIP_BnMMumbai ERC20 tokens to RxExchangeMumbai.sol to create an equal amount of liquidity for DuCCIPBnM token at Mumbai.
12. Finally, swap TGOLD -> DummyCCIP_BnM on Sepolia and wait for the CCIP message to be sent over to Mumbai to let DummyCCIP_BnMMumbai token to be trasnferred from the reserves of RxExchangeMumbai.sol to the desired address (e.g. trader's EOA on Mumabi) that was input as an argument in swapTGOLDToCCIPBnM() by the trrader itself.
13. Corresponding events are emitted at every step and custom errors have also been included at appropriate places.
===================================================================================================================

As this is an MVP project primarily meant to get the hang of Chainlink's Cross-Chain Interoperability Protocol so that it can be used in a real life utility / use case.

I coded the entire set of contracts from absolute scratch and was able to, finally, wrap my head around CCIP.
And, the Chainlink's docs have been immenselyt helpful before strating to code.
