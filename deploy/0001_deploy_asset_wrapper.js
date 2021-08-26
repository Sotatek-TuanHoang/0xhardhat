const { deployments, ethers } = require("hardhat");
const { erc20TokenInfo, erc721TokenInfo } = require("../src/utils/token_info");

const NULL_ADDRESS = "0x0000000000000000000000000000000000000000";

const func = async function ({ deployments, getNamedAccounts, getChainId }) {
  const { deploy, execute } = deployments;
  const { deployer } = await getNamedAccounts();

  const erc20Proxy = await deploy("ERC20Proxy", {
    from: deployer,
    args: [],
    log: true,
  });
  const erc721Proxy = await deploy("ERC721Proxy", {
    from: deployer,
    args: [],
    log: true,
  });

  const zrxToken = await deploy("DummyERC20Token", {
    from: deployer,
    args: ["0x Protocol Token", "ZRX", 18, "1000000000000000000000000000"],
    log: true,
  });

  const etherToken = await deploy("WETH9", {
    from: deployer,
    args: [],
    log: true,
  });

  const chainId = await getChainId();
  const exchange = await deploy("Exchange", {
    from: deployer,
    args: [chainId],
    log: true,
  });

  // Dummy ERC20 tokens
  for (const token of erc20TokenInfo) {
    const totalSupply = "1000000000000000000000000000";
    const dummyErc20Token = await deploy("DummyERC20Token", {
      from: deployer,
      args: [token.name, token.symbol, token.decimals.toString(), totalSupply],
      log: true,
    });
  }

  const cryptoKittieToken = await deploy("DummyERC721Token", {
    from: deployer,
    args: [erc721TokenInfo[0].name, erc721TokenInfo[0].symbol],
    log: true,
  });

  // 1155 Asset Proxy
  const erc1155Proxy = await deploy("ERC1155Proxy", {
    from: deployer,
    args: [],
    log: true,
  });

  const staticCallProxy = await deploy("StaticCallProxy", {
    from: deployer,
    args: [],
    log: true,
  });

  const multiAssetProxy = await deploy("MultiAssetProxy", {
    from: deployer,
    args: [],
    log: true,
  });

  await execute("ERC20Proxy", { from: deployer }, "addAuthorizedAddress", exchange.address);
  await execute("ERC721Proxy", { from: deployer }, "addAuthorizedAddress", exchange.address);
  await execute("ERC1155Proxy", { from: deployer }, "addAuthorizedAddress", exchange.address);
  await execute("MultiAssetProxy", { from: deployer }, "addAuthorizedAddress", exchange.address);

  // MultiAssetProxy
  await execute("ERC20Proxy", { from: deployer }, "addAuthorizedAddress", multiAssetProxy.address);
  await execute("ERC721Proxy", { from: deployer }, "addAuthorizedAddress", multiAssetProxy.address);
  await execute("ERC1155Proxy", { from: deployer }, "addAuthorizedAddress", multiAssetProxy.address);
  await execute("MultiAssetProxy", { from: deployer }, "registerAssetProxy", erc20Proxy.address);
  await execute("MultiAssetProxy", { from: deployer }, "registerAssetProxy", erc721Proxy.address);
  await execute("MultiAssetProxy", { from: deployer }, "registerAssetProxy", erc1155Proxy.address);
  await execute("MultiAssetProxy", { from: deployer }, "registerAssetProxy", staticCallProxy.address);

  await execute("Exchange", { from: deployer }, "registerAssetProxy", erc20Proxy.address);
  await execute("Exchange", { from: deployer }, "registerAssetProxy", erc721Proxy.address);
  await execute("Exchange", { from: deployer }, "registerAssetProxy", erc1155Proxy.address);
  await execute("Exchange", { from: deployer }, "registerAssetProxy", multiAssetProxy.address);
  await execute("Exchange", { from: deployer }, "registerAssetProxy", staticCallProxy.address);

  // CoordinatorRegistry
  const coordinatorRegistry = await deploy("CoordinatorRegistry", { from: deployer, log: true, args: [] });

  // Coordinator
  const coordinator = await deploy("Coordinator", {
    from: deployer,
    log: true,
    args: [exchange.address, chainId],
  });

  // Dev Utils
  const libAssetData = await deploy("LibAssetData", {
    from: deployer,
    log: true,
  });
  const libDydxBalance = await deploy("LibDydxBalance", {
    from: deployer,
    log: true,
    libraries: { LibAssetData: libAssetData.address },
  });
  const libOrderTransferSimulation = await deploy("LibOrderTransferSimulation", {
    from: deployer,
    log: true,
  });
  const libTransactionDecoder = await deploy("LibTransactionDecoder", {
    from: deployer,
    log: true,
  });
  const devUtils = await deploy("DevUtils", {
    from: deployer,
    log: true,
    args: [exchange.address, NULL_ADDRESS, NULL_ADDRESS],
    libraries: {
      LibAssetData: libAssetData.address,
      LibDydxBalance: libDydxBalance.address,
      LibOrderTransferSimulation: libOrderTransferSimulation.address,
      LibTransactionDecoder: libTransactionDecoder.address,
    },
  });

  const erc1155DummyToken = await deploy("ERC1155Mintable", {
    from: deployer,
    log: true,
  });
  const erc20BridgeProxy = await deploy("ERC20BridgeProxy", {
    from: deployer,
    log: true,
  });

  await execute("Exchange", { from: deployer }, "registerAssetProxy", erc20BridgeProxy.address);
  await execute("ERC20BridgeProxy", { from: deployer }, "addAuthorizedAddress", exchange.address);
  await execute("ERC20BridgeProxy", { from: deployer }, "addAuthorizedAddress", multiAssetProxy.address);
  await execute("MultiAssetProxy", { from: deployer }, "registerAssetProxy", erc20BridgeProxy.address);

  const zrxProxy = erc20Proxy.address;
  const zrxVault = await deploy("ZrxVault", {
    from: deployer,
    log: true,
    args: [zrxProxy, zrxToken.address],
  });

  // Note we use TestStakingContract as the deployed bytecode of a StakingContract
  // has the tokens hardcoded
  const stakingLogic = await deploy("TestStaking", {
    from: deployer,
    log: true,
    args: [etherToken.address, zrxVault.address],
  });

  const stakingProxy = await deploy("StakingProxy", {
    from: deployer,
    log: true,
    args: [stakingLogic.address],
  });

  await execute("ERC20Proxy", { from: deployer }, "addAuthorizedAddress", zrxVault.address);

  // Reference the Proxy as the StakingContract for setup
  const stakingDel = (await ethers.getContractFactory("TestStaking")).attach(stakingProxy.address);
  await execute("StakingProxy", { from: deployer }, "addAuthorizedAddress", deployer);
  await stakingDel.addExchangeAddress(exchange.address, { from: deployer });
  await execute("Exchange", { from: deployer }, "setProtocolFeeCollectorAddress", stakingProxy.address);
  await execute("Exchange", { from: deployer }, "setProtocolFeeMultiplier", "70000");

  await execute("ZrxVault", { from: deployer }, "addAuthorizedAddress", deployer);
  await execute("ZrxVault", { from: deployer }, "setStakingProxy", stakingProxy.address);
  await execute("TestStaking", { from: deployer }, "addAuthorizedAddress", deployer);
  await execute("TestStaking", { from: deployer }, "addExchangeAddress", exchange.address);

  // Forwarder
  // Deployed after Exchange and Staking is configured as it queries
  // in the constructor
  const exchangeV2 = exchange;
  const exchangeV2Address = exchangeV2.address;
  const forwarder = await deploy("Forwarder", {
    from: deployer,
    log: true,
    args: [exchange.address, exchangeV2Address || NULL_ADDRESS, etherToken.address],
  });

  // JAM
  const jamToken = await deploy("DummyERC20Token", {
    from: deployer,
    log: true,
    args: ["JAM Token", "JAM", 18, "1000000000000000000000000000"],
  });

  // Exchange Proxy //////////////////////////////////////////////////////////

  const bridgeAdapter = await deploy("BridgeAdapter", {
    from: deployer,
    log: true,
    args: [etherToken.address],
  });

  const migrator = await deploy("FullMigration", {
    from: deployer,
    log: true,
    args: [deployer],
  });
  // const zeroEx = await ZeroExContract.deployFrom0xArtifactAsync(
  //     artifacts.ZeroEx,
  //     provider,
  //     txDefaults,
  //     artifacts,
  //     await migrator.getBootstrapper().callAsync(),
  // );
  // const _config = { ...config, zeroExAddress: zeroEx.address };
  // const _features = await deployFullFeaturesAsync(provider, txDefaults, _config, features, featureArtifacts);
  // const migrateOpts = {
  //     transformerDeployer: txDefaults.from as string,
  //     ..._config,
  // };
  // await migrator.migrateZeroEx(owner, zeroEx.address, _features, migrateOpts).awaitTransactionSuccessAsync();
  // const exchangeProxy = await fullMigrateExchangeProxyAsync(txDefaults.from, provider, txDefaults);
  // const exchangeProxyFlashWalletAddress = await exchangeProxy.getTransformWallet().callAsync();

  // // Deploy transformers.
  // const wethTransformer = await WethTransformerContract.deployFrom0xArtifactAsync(
  //   exchangeProxyArtifacts.WethTransformer,
  //   provider,
  //   txDefaults,
  //   allArtifacts,
  //   etherToken.address
  // );
  // const payTakerTransformer = await PayTakerTransformerContract.deployFrom0xArtifactAsync(
  //   exchangeProxyArtifacts.PayTakerTransformer,
  //   provider,
  //   txDefaults,
  //   allArtifacts
  // );
  // const affiliateFeeTransformer = await AffiliateFeeTransformerContract.deployFrom0xArtifactAsync(
  //   exchangeProxyArtifacts.AffiliateFeeTransformer,
  //   provider,
  //   txDefaults,
  //   allArtifacts
  // );
  // const fillQuoteTransformer = await FillQuoteTransformerContract.deployFrom0xArtifactAsync(
  //   exchangeProxyArtifacts.FillQuoteTransformer,
  //   provider,
  //   txDefaults,
  //   allArtifacts,
  //   bridgeAdapter.address,
  //   exchangeProxy.address
  // );
  // const positiveSlippageFeeTransformer = await PositiveSlippageFeeTransformerContract.deployFrom0xArtifactAsync(
  //   exchangeProxyArtifacts.PositiveSlippageFeeTransformer,
  //   provider,
  //   txDefaults,
  //   allArtifacts
  // );
};

module.exports = func;
