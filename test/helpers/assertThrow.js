function assertError(error, s, message) {
  assert.isAbove(error.message.search(s), -1, message);
}

async function assertThrows(block, message, errorCode) {
      try {
          await block()
      } catch (e) {
          return assertError(e, errorCode, message)
      }
      assert.fail('should have thrown before')
}

module.exports = {
  async assertJump(block, message = 'should have failed with invalid JUMP') {
    return assertThrows(block, message, 'invalid JUMP')
  },

  async assertInvalidOpcode(block, message = 'should have failed with invalid opcode') {
    return assertThrows(block, message, 'invalid opcode')
  },

  async assertRevert(block, message = 'should have failed with revert') {
    return assertThrows(block, message, 'revert')
  },

  async assertSenderWithoutFunds(block, message = 'should have failed to send funds') {
    return assertThrows(block, message, 'sender doesn\'t have enough funds to send tx')
  }
}
