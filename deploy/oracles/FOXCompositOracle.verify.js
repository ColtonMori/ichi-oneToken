module.exports = async function({ ethers: { getNamedSigner }, getNamedAccounts, deployments }) {
    const { deploy } = deployments
  
    const { deployer, dev } = await getNamedAccounts()
  
    const chainId = await getChainId()

    const moduleType = {
        version: 0,
        controller: 1,
        strategy: 2,
        mintMaster: 3,
        oracle: 4,
        voterRoll: 5
    }

    const 
        name = 'TWAP FOX indexToken Uniswap V2 24hr/1hr',
        tokenAddress = '0xc770EEfAd204B5180dF6a14Ee197D99d808ee52d',  //FOX indextoken
        WETH = '0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2',
        TWAP_oracle = '0x0c07115E9cB4761b7e1246d42A2A6c0a8EDaA859',
        chainlink_oracle = '0xa5DEc9155960C278773BAE4aef071379Ca0a890B'

    //const
        //factory = await deployments.get("OneTokenFactory")
        //oracle = await deployments.get("ICHICompositeOracle")
    
    if (chainId != 31337) { //don't verify contract on localnet
        await hre.run("verify:verify", {
            address: '0x4b8eE384d444A0BD455f43672104aec4104089ad',
            constructorArguments: [
                '0xD0092632B9Ac5A7856664eeC1abb6E3403a6A36a',
                name,
                tokenAddress,
                [tokenAddress,WETH],
                [TWAP_oracle, chainlink_oracle]

            ],
        })
    }

}

module.exports.tags = ["FOXCompositeOracleVerify","verify"]
//