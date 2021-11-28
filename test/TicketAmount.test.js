const { assert } = require('chai');
const {
    BN,           // Big Number support
    constants,    // Common constants, like the zero address and largest integers
    expectEvent,  // Assertions for emitted events
    expectRevert,
    time 
  } = require('@openzeppelin/test-helpers');
const { web3 } = require('@openzeppelin/test-helpers/src/setup');

const HippoPrediction = artifacts.require("HippoPrediction");
const RandomNumberConsumer = artifacts.require("RandomNumberConsumer");
const Raffle = artifacts.require("Raffle");
const Reference = artifacts.require("Reference");
const PriceConsumerV3 = artifacts.require("PriceConsumerV3");
const MockPriceFeed = artifacts.require("MockV3Aggregator");


require('chai').use(require('chai-as-promised')).should();

function tokens(n){
    return web3.utils.toWei(n, 'ether');
}

let prediction, vrf, raffle, reference;
let priceConsumerV3, mockPriceFeed, price;

contract('HippoPrediction', ([owner, investor1, investor2, investor3, investor4]) => {
    
    beforeEach(async () => {
        price = tokens('2');
        mockPriceFeed = await MockPriceFeed.new(8, price);
        priceConsumerV3 = await PriceConsumerV3.new(mockPriceFeed.address);

        raffle = await Raffle.new(1800);
        vrf = await RandomNumberConsumer.new(raffle.address);
        raffle.setVRFAddress(vrf.address);

        reference = await Reference.new();

        prediction = await HippoPrediction.new([priceConsumerV3.address], 10, "100000",30,50,10,10,reference.address);
        prediction.setRaffleAddress(raffle.address);

        raffle.addAllowedAddress(prediction.address);
    })

    it('get ticket amounts', async () => {
        let log2;
        let amount;
        const norm = new BN('10000000000000000');

        amount = new BN('10000000000000000');
        log2 = await prediction.log2x(amount / norm);
        console.log(web3.utils.fromWei(amount), (15 * parseFloat(log2) / 10) + 1)

        amount = new BN('100000000000000000');
        log2 = await prediction.log2x(amount / norm);
        console.log(web3.utils.fromWei(amount), (15 * parseFloat(log2) / 10) + 1)

        amount = new BN('1000000000000000000');
        log2 = await prediction.log2x(amount / norm);
        console.log(web3.utils.fromWei(amount), (15 * parseFloat(log2) / 10) + 1)

        amount = new BN('10000000000000000000');
        log2 = await prediction.log2x(amount / norm);
        console.log(web3.utils.fromWei(amount), (15 * parseFloat(log2) / 10) + 1)

        amount = new BN('100000000000000000000');
        log2 = await prediction.log2x(amount / norm);
        console.log(web3.utils.fromWei(amount), (15 * parseFloat(log2) / 10) + 1)
        
        amount = new BN('100000000000000000000');
        log2 = await prediction.log2x(amount / norm);
        console.log(web3.utils.fromWei(amount), (15 * parseFloat(log2) / 10) + 1)
    })

});