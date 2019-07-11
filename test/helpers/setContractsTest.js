const { assertRevert } = require('./assertThrow');
// const SupplyPool = artifacts.require('SupplyPool');

module.exports = {
  setContractsTest: async (instance) => {
    let contracts = {
      // 'SupplyPool': await SupplyPool.new(),
    };

    for (let contractName in contracts) {
      if (contracts.hasOwnProperty(contractName)) {
        if(instance[`set${contractName}`]) {
          await instance[`set${contractName}`](contracts[contractName].address);
          await assertRevert(async () => {
            await instance[`set${contractName}`](instance.address);
          });
        }
      }
    }
    return true;
  }
};
