import { ethers, run } from "hardhat";

function sleep(milliseconds: number) {
  return new Promise((resolve) => setTimeout(resolve, milliseconds));
}

async function main() {

  const args = [
    "93503201847067459816865778983521324688116667814772937141130154736249866362126",
    {
      x: "0x722e78958ba8e8527e562c75829aed104de631fd6509ce5fc1f487782da40d32",
      parity: 0,
    },
    "0x4d831150A207bd6388cE78756CE7f14dcfB0E13E"
  ]

  const contract = await ethers.deployContract("DeRandCoordinator", args);

  await contract.deployed();

  console.log(
    `contract deployed to ${contract.address}`
  );
  
  await sleep(20000);

  await run("verify:verify", {
    address: contract.address,
    constructorArguments: args,
  });
}

// We recommend this pattern to be able to use async/await everywhere
// and properly handle errors.
main().catch((error) => {
  console.error(error);
  process.exitCode = 1;
});
