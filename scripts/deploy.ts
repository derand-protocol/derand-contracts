import { ethers } from "hardhat";

async function main() {

  const contract = await ethers.deployContract("DeRandCoordinator", [
    "19208182243350969302331310254348577926160425291544448432821516256936827443000",
    {
      x: "0x16d2b68efeb9eb76e61c781b4d0ad807f877c912814271ab173cd927e49888e8",
      parity: 1,
    },
    "0x6121A86157E776e4E6b5d7758E752F214Bf691d3"
  ]);

  await contract.deployed();

  console.log(
    `contract deployed to ${contract.address}`
  );
}

// We recommend this pattern to be able to use async/await everywhere
// and properly handle errors.
main().catch((error) => {
  console.error(error);
  process.exitCode = 1;
});
