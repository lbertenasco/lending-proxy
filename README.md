# Solidity Boilerplate
The basic idea behind the solidity boilerplate repo it's for anyone to have in 5 minutes a full compatible scaffolding based on Truffle & node, without the need of installing new packages, or copy pasting code from one place to another.

## What does solidity boilerplate include ?
* [Truffle](https://github.com/trufflesuite/truffle)
* [Ganache-cli](https://github.com/trufflesuite/ganache-cli)
* [OpenZeppelin-Solidity](https://github.com/OpenZeppelin/openzeppelin-solidity)
* [Commitizen](https://github.com/commitizen/cz-cli)
* [Standard Version](https://www.npmjs.com/package/standard-version)
* [Chai](https://github.com/chaijs/chai/)

## Scripts included

```bash
npm run compile
```
Will delete truffle build folder and re-compile your existing contracts.

```bash
npm run test
```
Will delete truffle build folder and execute all tests found in test/ folder.

```bash
npm run coveage
```
Same as **test** but will do a code coverage report.

## How to commit & make releases
Please refer to commitizen's & standard version in order to understand how to properly use it.
