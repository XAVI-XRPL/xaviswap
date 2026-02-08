const hre = require("hardhat");

async function main() {
  const [deployer] = await hre.ethers.getSigners();
  console.log("Redeploying XaviSwap v1.1.0 (Security Hardened)");
  console.log("Deployer:", deployer.address);
  
  const balance = await hre.ethers.provider.getBalance(deployer.address);
  console.log("Balance:", hre.ethers.formatEther(balance), "XRP\n");

  // 1. Deploy WXRP
  console.log("1. Deploying WXRP...");
  const WXRP = await hre.ethers.getContractFactory("WXRP");
  const wxrp = await WXRP.deploy();
  await wxrp.waitForDeployment();
  const wxrpAddress = await wxrp.getAddress();
  console.log("   WXRP:", wxrpAddress);

  // 2. Deploy Factory
  console.log("\n2. Deploying XaviFactory (with Pausable)...");
  const Factory = await hre.ethers.getContractFactory("XaviFactory");
  const factory = await Factory.deploy(deployer.address);
  await factory.waitForDeployment();
  const factoryAddress = await factory.getAddress();
  console.log("   XaviFactory:", factoryAddress);

  // 3. Deploy Router
  console.log("\n3. Deploying XaviRouter (with Pausable + MaxSwapPercent)...");
  const Router = await hre.ethers.getContractFactory("XaviRouter");
  const router = await Router.deploy(factoryAddress, wxrpAddress);
  await router.waitForDeployment();
  const routerAddress = await router.getAddress();
  console.log("   XaviRouter:", routerAddress);

  console.log("\n" + "=".repeat(60));
  console.log("XaviSwap v1.1.0 Deployment Complete!");
  console.log("=".repeat(60));
  console.log("WXRP:        ", wxrpAddress);
  console.log("Factory:     ", factoryAddress);
  console.log("Router:      ", routerAddress);
  console.log("Fee Recipient:", deployer.address);
  console.log("=".repeat(60));
  console.log("\nSecurity Features:");
  console.log("  ✓ Factory: Pausable, renounceOwnership disabled");
  console.log("  ✓ Router:  Pausable, deadline checks, maxSwapPercent (30%)");
  console.log("  ✓ Pair:    ReentrancyGuard, K-invariant, MINIMUM_LIQUIDITY locked");
  console.log("=".repeat(60));

  const finalBalance = await hre.ethers.provider.getBalance(deployer.address);
  console.log("\nGas used:", hre.ethers.formatEther(balance - finalBalance), "XRP");
  console.log("Remaining:", hre.ethers.formatEther(finalBalance), "XRP");
}

main()
  .then(() => process.exit(0))
  .catch((error) => {
    console.error(error);
    process.exit(1);
  });
