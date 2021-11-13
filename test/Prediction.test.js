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

    it('log2x check', async () => {
        let l;
        let t = 0.01;
        for(let i =0; i< 10; i++){
            l = await prediction.getLogAmount(tokens(t.toString()));
            console.log('tickets for bet '+t+ ' : ' +l.toString());
            t*=5;
        }
    })

    it('oracle returns a price', async () => {
        assert.equal(await priceConsumerV3.getLatestPrice(), price)
    })

    it('bet bull wins', async () => {

        await time.increase(10);
        await mockPriceFeed.updateAnswer(tokens('3'));

        await prediction.executeRound();

        const currentRound = await prediction.currentEpoch();

        await time.increase(1);
        
        await prediction.betBear(currentRound, {from:investor1, value:tokens('2.1')});
        await prediction.betBull(currentRound, {from:investor2, value:tokens('0.1')});

        await mockPriceFeed.updateAnswer(tokens('2'));
        await time.increase(10);

        //console.log(await web3.eth.getBalance(raffle.address));
        //console.log(await web3.eth.getBalance(prediction.address));
        

        await prediction.executeRound({from:investor1});


        //console.log(await web3.eth.getBalance(raffle.address));
        //console.log(await web3.eth.getBalance(prediction.address));

        await mockPriceFeed.updateAnswer(tokens('3'));

        await time.increase(12);
        await prediction.executeRound();

        //assert.equal(await prediction.claimable(currentRound, investor1), false);
        //assert.equal(await prediction.claimable(currentRound, investor2), true);


        //console.log(await web3.eth.getBalance(raffle.address));
        //console.log(await web3.eth.getBalance(prediction.address));

        await prediction.claim([currentRound], {from:investor2});

    })

    it('price stays same, both lose', async () => {

        await time.increase(10);
        await mockPriceFeed.updateAnswer(tokens('2'));

        await prediction.executeRound();
        
        const currentRound = await prediction.currentEpoch();

        await time.increase(5);
        await prediction.betBear(currentRound, {from:investor1, value:tokens('1')});
        await prediction.betBull(currentRound, {from:investor2, value:tokens('1')});

        await mockPriceFeed.updateAnswer(tokens('2'));
        await time.increase(5);
        await prediction.executeRound();

        await mockPriceFeed.updateAnswer(tokens('2'));
        await time.increase(10);
        await prediction.executeRound();

        assert.equal(await prediction.claimable(currentRound, investor1), false);
        assert.equal(await prediction.claimable(currentRound, investor2), false);
    })

    it('round couldnt execute, check refund', async () => {

        await mockPriceFeed.updateAnswer(tokens('2'));

        await time.increase(10);
        await prediction.executeRound();
        const currentRound = await prediction.currentEpoch();

        await time.increase(5);
        await prediction.betBear(currentRound, {from:investor1, value:tokens('1')});
        await prediction.betBull(currentRound, {from:investor2, value:tokens('1')});

        await time.increase(5);
        await prediction.executeRound();


        // await time.increase(11);

        // prediction.executeRound();

        // await time.increase(11);

        // prediction.executeRound();

        // assert.equal(await prediction.claimable(currentRound, investor1), false);
        // assert.equal(await prediction.claimable(currentRound, investor2), false);
        // assert.equal(await prediction.refundable(currentRound, investor1), true);
        // assert.equal(await prediction.refundable(currentRound, investor2), true);

        // await prediction.claim([currentRound], {from:investor1});
        // await prediction.claim([currentRound], {from:investor2});

    })

});