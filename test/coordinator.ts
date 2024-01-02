import { expect } from "chai";
import { ethers } from "hardhat";
// import { BigNumberish, ContractReceipt, BigNumber } from "ethers";
import { SignerWithAddress } from "@nomiclabs/hardhat-ethers/signers";

import { DeRandCoordinator, MuonClient } from "../typechain-types";
import axios from "axios";

const getDummySig = async (
  requestId: string,
  blockNum: number,
  callbackGasLimit: number,
  numWords: number,
  consumer: string
) => {
  const network = await ethers.provider.getNetwork();

  const response = await axios.get(
    `http://18.221.100.91:8011/v1/?app=vrf&method=random-number&params[chainId]=${network.chainId}&params[requestId]=${requestId}&params[blockNum]=${blockNum}&params[callbackGasLimit]=${callbackGasLimit}&params[numWords]=${numWords}&params[consumer]=${consumer}`
  );
  return response.data;
};

describe("DeRandCoordinator", function () {
  const ONE = ethers.utils.parseEther("1");

  let deployer: SignerWithAddress;
  let user: SignerWithAddress; 

  let muon: MuonClient;
  let coordinator: DeRandCoordinator;


  before(async () => {
    [deployer, user] =
      await ethers.getSigners();
  });

  beforeEach(async () => {

    const muonAppId = "19208182243350969302331310254348577926160425291544448432821516256936827443000";
    const muonPublicKey = {
      x: "0x16d2b68efeb9eb76e61c781b4d0ad807f877c912814271ab173cd927e49888e8",
      parity: 1,
    };

    const muonFactory = await ethers.getContractFactory("MuonClient");
    muon = await muonFactory.connect(deployer).deploy(
      muonAppId,
      muonPublicKey
    );
    await muon.deployed();

    const coordinatorFactory = await ethers.getContractFactory("DeRandCoordinator");
    coordinator = await coordinatorFactory.connect(deployer).deploy(
      muonAppId,
      muonPublicKey,
      muon.address
    );
    await coordinator.deployed();

    await coordinator.connect(deployer).setConfig(3, 2500000);
  });

  describe("Request", async function () {
    it("Should request random words", async function () {
      expect(
        await coordinator.requestRandomWords(
          "0x6e099d640cde6de9d40ac749b4b594126b0169747122711109c9985d47751f93",
          0,
          3,
          10000,
          2
        )
      ).to.not.reverted;
    });

    it("Should fulfill random words", async function () {
      const tx = await coordinator.requestRandomWords(
        "0x6e099d640cde6de9d40ac749b4b594126b0169747122711109c9985d47751f93",
        0,
        3,
        10000,
        2
      );
      const receipt = await tx.wait();
      if (receipt.events) {
        const event = receipt.events[0];
        const requestId = event.args?.requestId;
        const callbackGasLimit = event.args?.callbackGasLimit;
        const numWords = event.args?.numWords;
        const sender = event.args?.sender;
        const blockNum = receipt.blockNumber

        const dumySig = await getDummySig(
          requestId.toString(), blockNum, callbackGasLimit, numWords, sender
        );

        const reqId = dumySig["result"]["reqId"];
        const sig = {
          signature: dumySig["result"]["signatures"][0]["signature"],
          owner: dumySig["result"]["signatures"][0]["owner"],
          nonce: dumySig["result"]["data"]["init"]["nonceAddress"],
        };

        console.log(dumySig["result"]["data"]["signParams"]);
        console.log(dumySig["result"]["data"]["resultHash"]);
        console.log("---------------------");

        expect(
          await coordinator.fulfillRandomWords(
            requestId.toString(),
            {
              blockNum,
              callbackGasLimit,
              numWords,
              sender
            },
            reqId,
            sig
          )
        ).to.not.reverted;

      } else {
        throw ("Unable to parse receipt events")
      }
    });
  });
});
