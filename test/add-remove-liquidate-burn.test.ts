import { expect } from 'chai';
import {
  ERC20MintableInstance,
  MockCompoundOracleInstance,
  OptionsContractInstance,
  OptionsExchangeInstance,
  OptionsFactoryInstance
} from '../build/types/truffle-types';

const OptionsContract = artifacts.require('OptionsContract');
const OptionsFactory = artifacts.require('OptionsFactory');
const OptionsExchange = artifacts.require('OptionsExchange');
const MockCompoundOracle = artifacts.require('MockCompoundOracle');
const MockUniswapFactory = artifacts.require('MockUniswapFactory');
const MintableToken = artifacts.require('ERC20Mintable');

const {
  BN,
  constants,
  balance,
  time,
  expectEvent,
  expectRevert
} = require('@openzeppelin/test-helpers');

contract('OptionsContract', accounts => {
  const creatorAddress = accounts[0];
  const firstRepoOwnerAddress = accounts[1];
  const secondRepoOwnerAddress = accounts[2];

  const firstExerciser = accounts[3];
  const secondExerciser = accounts[4];

  const optionsContracts: OptionsContractInstance[] = [];
  let optionsFactory: OptionsFactoryInstance;
  let optionsExchange: OptionsExchangeInstance;
  let compoundOracle: MockCompoundOracleInstance;
  let dai: ERC20MintableInstance;
  let usdc: ERC20MintableInstance;

  const repo1Collateral = '20000000';
  const repo1PutsOutstanding = '250000';

  const repo2Collateral = '10000000';
  const repo2PutsOutstanding = '100000';

  before('set up contracts', async () => {
    // 1. Deploy mock contracts
    // 1.1 Compound Oracle
    compoundOracle = await MockCompoundOracle.new();
    // 1.2 Uniswap Factory
    const uniswapFactory = await MockUniswapFactory.new();
    // 1.3 Mock Dai contract
    dai = await MintableToken.new();
    await dai.mint(creatorAddress, '10000000');
    await dai.mint(firstExerciser, '100000', { from: creatorAddress });
    await dai.mint(secondExerciser, '100000', { from: creatorAddress });
    // 1.4 Mock Dai contract
    usdc = await MintableToken.new();
    await usdc.mint(creatorAddress, '10000000');
    // 2. Deploy our contracts
    // deploys the Options Exhange contract
    optionsExchange = await OptionsExchange.deployed();

    // TODO: remove this later. For now, set the compound Oracle and uniswap Factory addresses here.
    await optionsExchange.setUniswapAndCompound(
      uniswapFactory.address,
      compoundOracle.address
    );

    // Deploy the Options Factory contract and add assets to it
    optionsFactory = await OptionsFactory.deployed();
    await optionsFactory.setOptionsExchange(optionsExchange.address);

    await optionsFactory.addAsset('DAI', dai.address);
    // TODO: deploy a mock USDC and get its address
    await optionsFactory.addAsset('USDC', usdc.address);

    // Create the unexpired options contract
    const optionsContractResult = await optionsFactory.createOptionsContract(
      'ETH',
      -'18',
      'DAI',
      -'14',
      '9',
      -'15',
      'USDC',
      '1577836800',
      '1577836800'
    );

    const optionsContractAddr = optionsContractResult.logs[0].args[0];
    optionsContracts.push(await OptionsContract.at(optionsContractAddr));

    // Open Repo1, add Collateral and Mint oTokens
    await optionsContracts[0].openRepo({
      from: firstRepoOwnerAddress,
      gas: '100000'
    });

    await optionsContracts[0].addETHCollateral(0, {
      from: firstRepoOwnerAddress,
      gas: '100000',
      value: repo1Collateral
    });

    await optionsContracts[0].issueOptionTokens('0', repo1PutsOutstanding, {
      from: firstRepoOwnerAddress,
      gas: '100000'
    });

    await optionsContracts[0].transfer(firstExerciser, '10', {
      from: firstRepoOwnerAddress,
      gas: '100000'
    });

    // Open Repo2, add Collateral and Mint oTokens
    await optionsContracts[0].openRepo({
      from: secondRepoOwnerAddress,
      gas: '100000'
    });

    await optionsContracts[0].addETHCollateral(1, {
      from: secondRepoOwnerAddress,
      gas: '100000',
      value: repo2Collateral
    });

    await optionsContracts[0].issueOptionTokens(1, repo2PutsOutstanding, {
      from: secondRepoOwnerAddress,
      gas: '100000'
    });

    await optionsContracts[0].transfer(secondExerciser, '10', {
      from: secondRepoOwnerAddress,
      gas: '100000'
    });
  });

  describe('Scenario: Add + remove collateral + liquidate + burn tokens', () => {
    it('anyone should be able to add ETH collateral to Repo 2', async () => {
      let repoState = await optionsContracts[0].getRepoByIndex(1);
      const initialCollateral = new BN(repoState['0'].toString());

      await optionsContracts[0].addETHCollateral(1, {
        from: creatorAddress,
        gas: '100000',
        value: repo2Collateral
      });

      repoState = await optionsContracts[0].getRepoByIndex(1);
      const finalCollateral = new BN(repoState['0'].toString());

      expect(finalCollateral.toString()).to.equal(
        initialCollateral.add(new BN(repo2Collateral)).toString()
      );
    });

    it('repo 1 should be unsafe after Compund Oracle drops price', async () => {
      await compoundOracle.updatePrice(100, {
        from: creatorAddress,
        gas: '1000000'
      });

      const unsafe = await optionsContracts[0].isUnsafe(0);
      expect(unsafe).to.be.true;
    });

    it('repo 2 should be safe after Compund Oracle drops price', async () => {
      compoundOracle.updatePrice(100, {
        from: creatorAddress,
        gas: '1000000'
      });

      const unsafe = await optionsContracts[0].isUnsafe(1);
      expect(unsafe).to.be.false;
    });

    it('repo 1 should be safe after Compund Oracle reices price', async () => {
      await compoundOracle.updatePrice(200, {
        from: creatorAddress,
        gas: '1000000'
      });

      const unsafe = await optionsContracts[0].isUnsafe(0);
      expect(unsafe).to.be.false;
    });

    it('secondRepoOwnerAddress should be able to remove collateral', async () => {
      let repoState = await optionsContracts[0].getRepoByIndex(1);
      const initialCollateral = new BN(repoState['0'].toString());

      const result = await optionsContracts[0].removeCollateral(
        1,
        repo2Collateral,
        {
          from: secondRepoOwnerAddress,
          gas: '100000'
        }
      );

      repoState = await optionsContracts[0].getRepoByIndex(1);
      const finalCollateral = new BN(repoState['0'].toString());

      expect(finalCollateral.toString()).to.equal(
        initialCollateral.sub(new BN(repo2Collateral)).toString()
      );
    });

    it("firstRepoOwnerAddress shouldn't be able to remove collateral", async () => {
      await expectRevert(
        optionsContracts[0].removeCollateral(0, repo2Collateral, {
          from: firstRepoOwnerAddress,
          gas: '100000'
        }),
        'Repo is unsafe'
      );
    });

    it('repo 1 should be unsafe after Compund Oracle drops price', async () => {
      await compoundOracle.updatePrice(100, {
        from: creatorAddress,
        gas: '1000000'
      });

      const unsafe = await optionsContracts[0].isUnsafe(0);
      expect(unsafe).to.be.true;
    });

    it('repo 2 should be unsafe after Compund Oracle drops price', async () => {
      compoundOracle.updatePrice(100, {
        from: creatorAddress,
        gas: '1000000'
      });

      const unsafe = await optionsContracts[0].isUnsafe(1);
      expect(unsafe).to.be.true;
    });
  });
});
