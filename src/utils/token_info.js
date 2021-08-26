const { BigNumber, NULL_BYTES } = require("@0x/utils");

const erc20TokenInfo = [
  {
    name: "Augur Reputation Token",
    symbol: "REP",
    decimals: new BigNumber(18),
    ipfsHash: NULL_BYTES,
    swarmHash: NULL_BYTES,
  },
  {
    name: "Dai",
    symbol: "DAI",
    decimals: new BigNumber(18),
    ipfsHash: NULL_BYTES,
    swarmHash: NULL_BYTES,
  },
  {
    name: "Golem Network Token",
    symbol: "GNT",
    decimals: new BigNumber(18),
    ipfsHash: NULL_BYTES,
    swarmHash: NULL_BYTES,
  },
  {
    name: "MakerDAO",
    symbol: "MKR",
    decimals: new BigNumber(18),
    ipfsHash: NULL_BYTES,
    swarmHash: NULL_BYTES,
  },
  {
    name: "Melon Token",
    symbol: "MLN",
    decimals: new BigNumber(18),
    ipfsHash: NULL_BYTES,
    swarmHash: NULL_BYTES,
  },
];

const erc721TokenInfo = [
  {
    name: "0xen ERC721",
    symbol: "0xen",
  },
];

module.exports = { erc20TokenInfo, erc721TokenInfo };
