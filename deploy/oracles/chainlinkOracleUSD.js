const { network } = require('hardhat')

const { getCurrentConfig } = require('../../scripts/deployConfigs')

module.exports = async function({ getNamedAccounts, deployments }) {
    const { deploy, execute, get } = deployments
  
    const { deployer } = await getNamedAccounts()

    const moduleType = {
        version: 0,
        controller: 1,
        strategy: 2,
        mintMaster: 3,
        oracle: 4,
        voterRoll: 5
    }

    const 
        name = 'Chainlink Oracle USD',
        url = 'https://data.chain.link/?search=USD'

    const config = getCurrentConfig()

    const factory = await get("OneTokenFactory")

    const oracle = await deploy('ChainlinkOracleUSD', {
        from: deployer,
        args: [factory.address, name, config.usdc],  
        log: true
    })

    // admit oracle
    await execute(
        'OneTokenFactory',
        { from: deployer, log: true },
        'admitModule',
        oracle.address,
        moduleType.oracle,
        name,
        url
    )

    // admit usdc as collateral
    await execute(
        'OneTokenFactory',
        { from: deployer, log: true },
        'admitForeignToken',
        config.usdc,
        true,
        oracle.address
    )
}

module.exports.tags = ["chainlinkOracleUSD", "polygon"]
module.exports.dependencies = ["oneTokenFactory"]