import { HardhatUserConfig, task } from "hardhat/config";
import "@nomicfoundation/hardhat-toolbox";
import { HttpNetworkUserConfig } from "hardhat/types";

require('dotenv').config();
const Web3 = require('web3');

const networks: { [networkName: string]: HttpNetworkUserConfig } = {
  sepolia: {
    url: "https://rpc.ankr.com/eth_sepolia",
    chainId: 11155111,
    accounts: [process.env.PRIVATE_KEY || missing_privateKey()!]
  },
  goerli: {
    url: "https://rpc.ankr.com/eth_goerli",
    chainId: 5,
    accounts: [process.env.PRIVATE_KEY || missing_privateKey()!]
  },
  bscTestnet: {
    url: "https://bsc-testnet.publicnode.com",
    chainId: 97,
    accounts: [process.env.PRIVATE_KEY || missing_privateKey()!]
  },
  polygon: {
    url: `https://rpc.ankr.com/polygon/${process.env.ANKR_KEY}`,
    chainId: 137,
    accounts: [process.env.PRIVATE_KEY || missing_privateKey()!]
  },
  polygonMumbai: {
    url: `https://rpc.ankr.com/polygon_mumbai/`,
    chainId: 80001,
    accounts: [process.env.PRIVATE_KEY || missing_privateKey()!]
  },
  optimisticEthereum: {
    url: `https://rpc.ankr.com/optimism/${process.env.ANKR_KEY}`,
    chainId: 10,
    accounts: [process.env.PRIVATE_KEY || missing_privateKey()!]
  },
  avalancheFujiTestnet: {
    url: `https://rpc.ankr.com/avalanche_fuji/${process.env.ANKR_KEY}`,
    chainId: 43113,
    accounts: [process.env.PRIVATE_KEY || missing_privateKey()!]
  }
}

function missing_privateKey() {
  throw Error('PrivateKey missing')
}

task("account", "returns nonce and balance for specified address on multiple networks")
  .addParam("address")
  .setAction(async (taskArgs: {address: string}) => {
    

    let resultArr  = Object.keys(networks).map(async network => {
      const config = networks[network];
      const web3 = new Web3(config['url']);

      const nonce = await web3.eth.getTransactionCount(taskArgs.address, "latest");
      const balance = await web3.eth.getBalance(taskArgs.address);

      return [
        network, 
        nonce, 
        parseFloat(web3.utils.fromWei(balance, "ether")).toFixed(2) + "ETH"
      ]

    });

    await Promise.all(resultArr).then((resultArr) => {
      resultArr.unshift(["NETWORK | NONCE | BALANCE"]);
      console.log(resultArr);
    });

  });


task("verify-cli", "verify contract on the specified network")
  .addParam("address")
  .addParam("name")
  .setAction(async (taskArgs: {address: string, name: string}) => {
    
    const verify = require("./scripts/verify");

    await verify(taskArgs.address, `contracts/${taskArgs.name}.sol:${taskArgs.name}`);

  });

const config: HardhatUserConfig = {
  defaultNetwork: "hardhat",
  networks: {
    hardhat: {
    },
    ...networks
  },
  solidity: {
    version: "0.8.20",
    settings: {
      optimizer: {
        enabled: true,
        runs: 200,
      },
      viaIR: true
    }
  },
  paths: {
    sources: "./contracts",
    tests: "./test",
    cache: "./cache",
    artifacts: "./artifacts"
  },
  mocha: {
    timeout: 40000
  },
  etherscan: {
    apiKey: {
      mainnet: process.env.ETHERSCAN_KEY || "",
      sepolia: process.env.ETHERSCAN_KEY || "",
      goerli: process.env.ETHERSCAN_KEY || "",
      bscTestnet: process.env.BSCSCAN_KEY || "",
      polygon: process.env.POLYGON_KEY || "",
      polygonMumbai: process.env.POLYGON_KEY || "",
      optimisticEthereum: process.env.OPTIMISM_KEY || "",
      avalancheFujiTestnet: process.env.AVALANCHE_KEY || ""
    },
    customChains: [
      {
        network: "ftm",
        chainId: 250,
        urls: {
          apiURL: "https://ftmscan.com/",
          browserURL: "https://ftmscan.com/",
        },
      },
    ]
  },
};

export default config;
