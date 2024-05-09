import { ethers, run } from "hardhat";

function sleep(milliseconds: number) {
  return new Promise((resolve) => setTimeout(resolve, milliseconds));
}

async function main() {

  const args = [
    "0xb8067235c9b71FeeC069Af151Fdf0975dfBDFBA5",
    "93503201847067459816865778983521324688116667814772937141130154736249866362126",
    {
      x: "0x4182885822fe798509811091b5b6300299deae3d98a771cc179c2ffd11dabebb",
      parity: 1,
    },
    "0x4d831150A207bd6388cE78756CE7f14dcfB0E13E"
  ]

  const contract = await ethers.deployContract("DeRandConsumerExample", args);

  await contract.deployed();

  console.log(
    `contract deployed to ${contract.address}`
  );
  
  await sleep(20000);

  await run("verify:verify", {
    address: contract.address,
    constructorArguments: args,
    // contract: "contracts/muon/MuonClient.sol:MuonClient"
  });
}

// We recommend this pattern to be able to use async/await everywhere
// and properly handle errors.
main().catch((error) => {
  console.error(error);
  process.exitCode = 1;
});
