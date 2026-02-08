const hre = require("hardhat");

async function main() {
  const [deployer] = await hre.ethers.getSigners();
  console.log("Deploying XaviSwap with account:", deployer.address);
  
  const balance = await hre.ethers.provider.getBalance(deployer.address);
  console.log("Account balance:", hre.ethers.formatEther(balance), "XRP\n");

  // 1. Deploy WXRP (Wrapped XRP)
  console.log("1. Deploying WXRP...");
  const WXRP = await hre.ethers.getContractFactory("WXRP");
  const wxrp = await WXRP.deploy();
  await wxrp.waitForDeployment();
  const wxrpAddress = await wxrp.getAddress();
  console.log("   WXRP deployed to:", wxrpAddress);

  // 2. Deploy XaviFactory
  console.log("\n2. Deploying XaviFactory...");
  const XaviFactory = await hre.ethers.getContractFactory("XaviFactory");
  const factory = await XaviFactory.deploy(deployer.address);
  await factory.waitForDeployment();
  const factoryAddress = await factory.getAddress();
  console.log("   XaviFactory deployed to:", factoryAddress);
  console.log("   Fee recipient:", deployer.address);

  // 3. Deploy XaviRouter
  console.log("\n3. Deploying XaviRouter...");
  const XaviRouter = await hre.ethers.getContractFactory("XaviRouter");
  const router = await XaviRouter.deploy(factoryAddress, wxrpAddress);
  await router.waitForDeployment();
  const routerAddress = await router.getAddress();
  console.log("   XaviRouter deployed to:", routerAddress);

  console.log("\n========================================");
  console.log("XaviSwap Deployment Complete!");
  console.log("========================================");
  console.log("WXRP:        ", wxrpAddress);
  console.log("Factory:     ", factoryAddress);
  console.log("Router:      ", routerAddress);
  console.log("Fee Recipient:", deployer.address);
  console.log("========================================\n");

  // Check remaining balance
  const finalBalance = await hre.ethers.provider.getBalance(deployer.address);
  console.log("Gas used:", hre.ethers.formatEther(balance - finalBalance), "XRP");
  console.log("Remaining balance:", hre.ethers.formatEther(finalBalance), "XRP");
}

main()
  .then(() => process.exit(0))
  .catch((error) => {
    console.error(error);
    process.exit(1);
  });
