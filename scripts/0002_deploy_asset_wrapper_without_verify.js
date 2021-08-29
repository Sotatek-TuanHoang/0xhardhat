const { deployments, ethers, artifacts } = require("hardhat");
const { erc20TokenInfo, erc721TokenInfo } = require("../src/utils/token_info");
const IZeroEx = artifacts.require('IZeroEx');
const FullMigration = artifacts.require('FullMigration');

const NULL_ADDRESS = "0x0000000000000000000000000000000000000000";

const func = async function ({ deployments, getNamedAccounts, getChainId }) {
  const { deploy, execute } = deployments;
  const { deployer } = await getNamedAccounts();
  const txDefaultObj = {
    gas: 8000000,
    from: deployer,
    gasPrice: 100000000, // for bsc
  };

  const erc20Proxy = await deploy("ERC20Proxy", {
    from: deployer,
    args: [],
    log: true,
  });

  await hre.run('verify:verify', {
    address: erc20Proxy.address,
    constructorArguments: [],
  })

  const zrxToken = await deploy("DummyERC20Token", {
    from: deployer,
    args: ["0x Protocol Token", "ZRX", 18, "1000000000000000000000000000"],
    log: true,
  });

  await hre.run('verify:verify', {
    address: zrxToken.address,
    constructorArguments: ["0x Protocol Token", "ZRX", 18, "1000000000000000000000000000"],
  })


  const abcToken = await deploy("DummyERC20Token", {
    from: deployer,
    args: ["ABC TOKEN", "ABC", 18, "1000000000000000000000000000"],
    log: true,
  });

  await hre.run('verify:verify', {
    address: abcToken.address,
    constructorArguments: ["ABC TOKEN", "ABC", 18, "1000000000000000000000000000"],
  })

  // const etherToken = await deploy("WETH9", {
  //   from: deployer,
  //   args: [],
  //   log: true,
  // });

  // await hre.run('verify:verify', {
  //   address: etherToken.address,
  //   constructorArguments: [],
  // })

  const etherToken = {
    'address': '0x4fac0386c4045b52756b206db3148201e42b3f62'
  };

  // Dummy ERC20 tokens
  // for (const token of erc20TokenInfo) {
  //   const totalSupply = "1000000000000000000000000000";
  //   const dummyErc20Token = await deploy("DummyERC20Token", {
  //     from: deployer,
  //     args: [token.name, token.symbol, token.decimals.toString(), totalSupply],
  //     log: true,
  //   });

  //   await hre.run('verify:verify', {
  //     address: dummyErc20Token.address,
  //     constructorArguments: [token.name, token.symbol, token.decimals.toString(), totalSupply],
  //   })
  // }

  const staticCallProxy = await deploy("StaticCallProxy", {
    from: deployer,
    args: [],
    log: true,
  });

  await hre.run('verify:verify', {
    address: staticCallProxy.address,
    constructorArguments: [],
  })

  // Exchange Proxy //////////////////////////////////////////////////////////

  await hre.run("set:compile:one", { contractName: "BridgeAdapter"});

  const bridgeAdapter = await deploy("BridgeAdapter", {
    from: deployer,
    log: true,
    args: [etherToken.address],
  });

  await hre.run('verify:verify', {
    address: bridgeAdapter.address,
    constructorArguments: [etherToken.address],
  })


  // const migrator = await deploy("FullMigration", {
  //   from: deployer,
  //   log: true,
  //   args: [deployer],
  // });

  await hre.run("set:compile:one", { contractName: "FullMigration"});
  const migrator = await FullMigration.new(deployer);

  await hre.run('verify:verify', {
    address: migrator.address,
    constructorArguments: [deployer],
  })
  console.log("Migrator deployed to: ", migrator.address);

  const getBootstrapper = await migrator.getBootstrapper();

  await hre.run("set:compile:one", { contractName: "ZeroEx"});
  const zeroEx = await deploy("ZeroEx", {
    from: deployer,
    log: true,
    args: [getBootstrapper]
  });

  await hre.run('verify:verify', {
    address: zeroEx.address,
    constructorArguments: [getBootstrapper],
  })

  const _config = {
    zeroExAddress: zeroEx.address,
    wethAddress: etherToken.address,
    stakingAddress: NULL_ADDRESS,
    protocolFeeMultiplier: '100',
    transformerDeployer: txDefaultObj.from
  }

  await hre.run("set:compile:one", { contractName: "FeeCollectorController"});
  const feeCollectorController = await deploy("FeeCollectorController", {
    from: deployer,
    log: true,
    args: [etherToken.address, _config.stakingAddress],
  });

  await hre.run('verify:verify', {
    address: feeCollectorController.address,
    constructorArguments: [etherToken.address, _config.stakingAddress],
  })

  await hre.run("set:compile:one", { contractName: "TransformERC20Feature"});
  const transformERC20 = await deploy("TransformERC20Feature", {
    from: deployer,
    log: true,
    args: [],
  });

  await hre.run('verify:verify', {
    address: transformERC20.address,
    constructorArguments: [],
  })
  
  await hre.run("set:compile:one", { contractName: "NativeOrdersFeature"});
  const nativeOrders = await deploy("NativeOrdersFeature", {
    from: deployer,
    log: true,
    args: [_config.zeroExAddress, _config.wethAddress, _config.stakingAddress, feeCollectorController.address, _config.protocolFeeMultiplier],
  });
  
  await hre.run('verify:verify', {
    address: nativeOrders.address,
    constructorArguments: [_config.zeroExAddress, _config.wethAddress, _config.stakingAddress, feeCollectorController.address, _config.protocolFeeMultiplier],
  })

  await hre.run("set:compile:one", { contractName: "MatchOrdersFeature"});
  const matchOrders = await deploy("MatchOrdersFeature", {
    from: deployer,
    log: true,
    args: [_config.zeroExAddress],
  });

  await hre.run('verify:verify', {
    address: matchOrders.address,
    constructorArguments: [_config.zeroExAddress],
  })
  
  await hre.run("set:compile:one", { contractName: "LimitOrderFeature"});
  const limitOrder = await deploy("LimitOrderFeature", {
    from: deployer,
    log: true,
    args: [_config.zeroExAddress],
  });

  await hre.run('verify:verify', {
    address: limitOrder.address,
    constructorArguments: [_config.zeroExAddress],
  })
  
  await hre.run("set:compile:one", { contractName: "SimpleFunctionRegistryFeature"});
  const registry = await deploy("SimpleFunctionRegistryFeature", {
    from: deployer,
    log: true,
    args: [],
  });

  await hre.run('verify:verify', {
    address: registry.address,
    constructorArguments: [],
  })
  
  await hre.run("set:compile:one", { contractName: "OwnableFeature"});
  const ownable = await deploy("OwnableFeature", {
    from: deployer,
    log: true,
    args: [],
  });

  await hre.run('verify:verify', {
    address: ownable.address,
    constructorArguments: [],
  })

  const _features = {
    registry: registry.address,
    ownable: ownable.address,
    transformERC20: transformERC20.address,
    nativeOrders: nativeOrders.address,
    matchOrders: matchOrders.address,
    limitOrder: limitOrder.address
  };



  await migrator.migrateZeroEx(deployer, zeroEx.address, _features, _config);


  const exchangeProxy = IZeroEx.at(zeroEx.address);

  await hre.run("set:compile:one", { contractName: "WethTransformer"});
  const wethTransformer = await deploy("WethTransformer", {
    from: deployer,
    log: true,
    args: [etherToken.address],
  });

  await hre.run('verify:verify', {
    address: wethTransformer.address,
    constructorArguments: [etherToken.address],
  })

  await hre.run("set:compile:one", { contractName: "PayTakerTransformer"});
  const payTakerTransformer = await deploy("PayTakerTransformer", {
    from: deployer,
    log: true,
    args: [],
  });

  await hre.run('verify:verify', {
    address: payTakerTransformer.address,
    constructorArguments: [],
  })


  await hre.run("set:compile:one", { contractName: "AffiliateFeeTransformer"});
  const affiliateFeeTransformer = await deploy("AffiliateFeeTransformer", {
    from: deployer,
    log: true,
    args: [],
  });

  await hre.run('verify:verify', {
    address: affiliateFeeTransformer.address,
    constructorArguments: [],
  })

  await hre.run("set:compile:one", { contractName: "FillQuoteTransformer"});
  const fillQuoteTransformer = await deploy("FillQuoteTransformer", {
    from: deployer,
    log: true,
    args: [bridgeAdapter.address, zeroEx.address],
  });

  await hre.run('verify:verify', {
    address: fillQuoteTransformer.address,
    constructorArguments: [bridgeAdapter.address, zeroEx.address],
  })

  await hre.run("set:compile:one", { contractName: "PositiveSlippageFeeTransformer"});
  const positiveSlippageFeeTransformer = await deploy("PositiveSlippageFeeTransformer", {
    from: deployer,
    log: true,
    args: [],
  });

  await hre.run('verify:verify', {
    address: positiveSlippageFeeTransformer.address,
    constructorArguments: [],
  })

  console.log("----------------COPY HERE------------------>");
  console.log(`ERC20_PROXY=${erc20Proxy.address}`);
  console.log(`ZRX_TOKEN=${zrxToken.address}`);
  console.log(`STATIC_CALL_PROXY=${staticCallProxy.address}`);
  console.log(`ZRX_VAULT=${NULL_ADDRESS}`);
  console.log(`EXCHANGE_PROXY=${zeroEx.address}`);
  console.log(`EXCHANGE_PROXY_TRANSFORMER_DEPLOYER=${txDefaultObj.from}`);
  console.log(`EXCHANGE_PROXY_FLASH_WALLET=${NULL_ADDRESS}`);
  console.log(`PAY_TAKER_TRANSFORMER=${payTakerTransformer.address}`);
  console.log(`AFFILIATE_FEE_TRANSFORMER=${affiliateFeeTransformer.address}`);
  console.log(`POSITIVE_SLIPPAGE_FEE_TRANSFORMER=${positiveSlippageFeeTransformer.address}`);
  console.log(`DEFAULT_PROPERTY_CONTRACT_VALUE=0x0000000000000000000000000000000000000000`);
  console.log(`ABC_TOKEN=${abcToken.address}`);

  console.log(`REGISTRY=${_features.registry}`);
  console.log(`OWNABLE=${_features.ownable}`);
  console.log(`TRANSFORM_ERC20=${_features.transformERC20}`);
  console.log(`NATIVE_ORDERS=${_features.nativeOrders}`);
  console.log(`MATCH_ORDERS=${_features.matchOrders}`);
  console.log(`LIMIT_ORDER=${_features.limitOrder}`);
  console.log("----------------END HERE------------------>");
};

module.exports = func;
