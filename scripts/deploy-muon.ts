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
    }
  ]

  const contract = await ethers.deployContract("MuonClient", args);

  await contract.deployed();

  console.log(
    `contract deployed to ${contract.address}`
  );
  
  await sleep(20000);

  await run("verify:verify", {
    address: contract.address,
    constructorArguments: args,
    contract: "contracts/muon/MuonClient.sol:MuonClient"
  });
}

// We recommend this pattern to be able to use async/await everywhere
// and properly handle errors.
main().catch((error) => {
  console.error(error);
  process.exitCode = 1;
});
