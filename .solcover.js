module.exports = {
    copyPackages: [
      'openzeppelin-solidity',
    ],
    norpc: true,
    skipFiles: [
      'Migrations.sol',
      'compound/CErc20.sol',
      'compound/ComptrollerInterface.sol',
      'compound/EIP20NonStandardInterface.sol',
      'compound/InterestRateModel.sol',
      'compound/Unitroller.sol',
      'compound/CToken.sol',
      'compound/ComptrollerStorage.sol',
      'compound/ErrorReporter.sol',
      'compound/PriceOracle.sol',
      'compound/WhitePaperInterestRateModel.sol',
      'compound/CarefulMath.sol',
      'compound/EIP20Interface.sol',
      'compound/Exponential.sol',
      'compound/ReentrancyGuard.sol',
    ],
    testCommand: 'node --max-old-space-size=4096 ../node_modules/.bin/truffle test --network coverage',
};
