require('chai/register-should'); // Register chai test helper

let exportConfig = {
  networks: {
    development: {
      host: "localhost",
      port: 8545,
      gas: 7000000,
      network_id: "*"
    },
    ganache: {
      host: "localhost",
      port: 8345,
      gas: 7000000,
      network_id: "*"
    },
    coverage: {
      host: "localhost",
      network_id: "*",
      port: 8355,         // <-- Use port 8555
      gas: 0xfffffffffff, // <-- Use this high gas value
      gasPrice: 0x01      // <-- Use this low gas price
    }
  },
  solc: {
    optimizer: {
      enabled: true,
      runs: 200
    }
  }
};

if (!process.env.SOLIDITY_COVERAGE && !process.env.SOLIDITY_TEST) {
  exportConfig.mocha = {
    reporter: 'eth-gas-reporter',
    reporterOptions : {
      currency: 'USD',
    }
  };
}

module.exports = exportConfig;
