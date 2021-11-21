const HippoPrediction = artifacts.require("HippoPrediction");
const RandomNumberConsumer = artifacts.require("RandomNumberConsumer");
const Raffle = artifacts.require("Raffle");
const Reference = artifacts.require("Reference");

module.exports = async function(deployer, network, accounts) {
    await deployer.deploy(Reference);
    const reference = await Reference.deployed();

    await deployer.deploy(Raffle, 1800);
    const raffle = await Raffle.deployed();

    await deployer.deploy(RandomNumberConsumer, raffle.address);
    const vrf = await RandomNumberConsumer.deployed();


    const oracleAddresses = ["0xB8ce593E3C94Ad25Bc87D7e3e484C98A4A82335E",
    "0x0FCAa9c899EC5A91eBc3D5Dd869De833b06fB046",
    "0x0715A7794a1dc8e42615F059dD6e406A6594651A",
    "0x12162c3E810393dEC01362aBf156D7ecf6159528",
    "0xd0D5e3DB44DE05E9F294BB0a3bEEaF030DE24Ada"];


    await deployer.deploy(HippoPrediction, oracleAddresses, 300, '100000', 30, 50, 10, 10, reference.address);
    const prediction = await HippoPrediction.deployed();

    prediction.setRaffleAddress(raffle.address);
    raffle.setVRFAddress(vrf.address);
    raffle.addAllowedAddress(prediction.address);

    console.log('Addresses');
    console.log('Prediction: ',prediction.address);
    console.log('Reference: ',reference.address);
    console.log('Raffle: ',raffle.address);
    console.log('RandomNumberConsumer: ',vrf.address);
    
};
    