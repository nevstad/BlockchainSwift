import XCTest
@testable import BlockchainSwift
import GRDB

final class BlockchainSwiftTests: XCTestCase {
    
    class MessageListenerTestDelegate: MessageListenerDelegate {
        var version: Bool = false
        var transactions: [Transaction] = []
        var getTransactions: Bool = false
        var blocks: [Block] = []
        var getBlocks: Bool = false
        var ping: Bool = false
        var pong: Bool = false
        func didReceiveVersionMessage(_ message: VersionMessage, from: NodeAddress) { version = true }
        func didReceiveGetTransactionsMessage(_ message: GetTransactionsMessage, from: NodeAddress) { getTransactions = true }
        func didReceiveTransactionsMessage(_ message: TransactionsMessage, from: NodeAddress) { transactions = message.transactions }
        func didReceiveGetBlocksMessage(_ message: GetBlocksMessage, from: NodeAddress) { getBlocks = true }
        func didReceiveBlocksMessage(_ message: BlocksMessage, from: NodeAddress) { blocks = message.blocks }
        func didReceivePingMessage(_ message: PingMessage, from: NodeAddress) { ping = true }
        func didReceivePongMessage(_ message: PongMessage, from: NodeAddress) { pong = true }
    }

    class MockNetwork {
        static func randomNetwork() -> (network: NWNetwork, delegate: MessageListenerTestDelegate, port: UInt32) {
            let delegate = MessageListenerTestDelegate()
            let port = NodeAddress.randomPort()
            let network = NWNetwork(port: port)
            network.delegate = delegate
            network.start()
            return (network: network, delegate: delegate, port: port)
        }
        #if canImport(NIO)
        static func randomNIO() -> (network: NIONetwork, delegate: MessageListenerTestDelegate, port: UInt32) {
            let delegate = MessageListenerTestDelegate()
            let port = NodeAddress.randomPort()
            let network = NIONetwork(port: Int(port))
            network.delegate = delegate
            network.start()
            return (network: network, delegate: delegate, port: port)
        }
        #endif
    }
    

    func testKeyGenAndTxSigning() {
        if let keyPair = Keygen.generateKeyPair(name: "TempPair") {
            if let pubKeyData = Keygen.copyExternalRepresentation(key: keyPair.publicKey) {
                let address = pubKeyData.sha256().sha256()
                let utxo = TransactionOutput(value: 100, address: address)
                let utxoHash = utxo.serialized().sha256()
                // Create a transaction and sign it, making sure first the sender has the right to claim the spendale outputs
                guard let signature1 = try? Keysign.sign(data: utxoHash, with: keyPair.privateKey) else {
                    XCTFail("Could not sign with original key")
                    return
                }
                let verified1 = Keysign.verify(publicKey: pubKeyData, data: utxoHash, signature: signature1)
                XCTAssert(verified1, "Unable to verify signature1")
            } else {
                XCTFail("Failed to restore key pair")
            }
        } else {
            XCTFail("Could not generate key pair")
        }
    }
    
    func testKeyRestoreData() {
        if let keyPair = Keygen.generateKeyPair(name: "TempPair"),
            let privKeyData = Keygen.copyExternalRepresentation(key: keyPair.privateKey),
            let pubKeyData = Keygen.copyExternalRepresentation(key: keyPair.publicKey) {
            if let restoredKeyPair = Keygen.generateKeyPair(name: "TempPair", privateKeyData: privKeyData),
                let restoredPrivKeyData = Keygen.copyExternalRepresentation(key: restoredKeyPair.privateKey),
                let restoredPubKeyData = Keygen.copyExternalRepresentation(key: restoredKeyPair.publicKey) {
                XCTAssert(privKeyData.hex == restoredPrivKeyData.hex, "Mismatching private keys")
                XCTAssert(pubKeyData.hex == restoredPubKeyData.hex, "Mismatching public keys")
            } else {
                XCTFail("Could not restore key pair")
            }
        } else {
            XCTFail("Could not generate key pair")
        }
    }
    
    func testKeyRestoreHex() {
        if let keyPair = Keygen.generateKeyPair(name: "TempPair"),
            let privKeyData = Keygen.copyExternalRepresentation(key: keyPair.privateKey),
            let pubKeyData = Keygen.copyExternalRepresentation(key: keyPair.publicKey) {
            if let restoredKeyPair = Keygen.generateKeyPair(name: "TempPairRestored", privateKeyHex: privKeyData.hex),
                let restoredPrivKeyData = Keygen.copyExternalRepresentation(key: restoredKeyPair.privateKey),
                let restoredPubKeyData = Keygen.copyExternalRepresentation(key: restoredKeyPair.publicKey) {
                XCTAssert(privKeyData.hex == restoredPrivKeyData.hex, "Mismatching private keys")
                XCTAssert(pubKeyData.hex == restoredPubKeyData.hex, "Mismatching public keys")
            } else {
                XCTFail("Could not restore key pair")
            }
        } else {
            XCTFail("Could not generate key pair")
        }
    }
    
    func testWalletStore() {
        let wallet = Wallet(name: "TempPair", storeInKeychain: true)!
        let duplicateWallet = Wallet(name: "TempPair")!
        let duplicateEqualToOriginal =
            wallet.secPrivateKey == duplicateWallet.secPrivateKey &&
                wallet.secPublicKey == duplicateWallet.secPublicKey &&
                wallet.publicKey == duplicateWallet.publicKey &&
                wallet.address == duplicateWallet.address
        XCTAssert(duplicateEqualToOriginal)
        let restoredKeyPair = Keygen.loadKeyPairFromKeychain(name: "TempPair")!
        Keygen.clearKeychainKeys(name: "TempPair")
        let failedRestorePair = Keygen.loadKeyPairFromKeychain(name: "TempPair")
        XCTAssert(failedRestorePair == nil)
        let restoredWallet = Wallet(name: "TempPair", keyPair: restoredKeyPair)
        let restoreEqualToOriginal =
            wallet.secPrivateKey == restoredWallet.secPrivateKey &&
            wallet.secPublicKey == restoredWallet.secPublicKey &&
            wallet.publicKey == restoredWallet.publicKey &&
            wallet.address == restoredWallet.address
        XCTAssert(restoreEqualToOriginal)
    }
    
    func testWalletFromKeychainAndTxSigning() {
        let node = Node()
        let wallet1 = Wallet(name: "test", storeInKeychain: true)!
        defer { Keygen.clearKeychainKeys(name: "test") }
        let wallet2 = Wallet(name: "test2", keyPair: Keygen.loadKeyPairFromKeychain(name: "test")!)
        let wallet3 = Wallet(name: "test3")!
        let _ = try? node.mineBlock(minerAddress: wallet1.address)
        let tx1 = try? node.createTransaction(sender: wallet1, recipientAddress: wallet3.address, value: 1)
        let tx2 = try? node.createTransaction(sender: wallet2, recipientAddress: wallet3.address, value: 1)
        XCTAssert(tx1 != nil, "Could not create tx with original wallet")
        XCTAssert(tx2 != nil, "Could not create tx with restored wallet")
    }
    
    func testKeyRestoreFromDataAndTxSigning() {
        if let keyPair = Keygen.generateKeyPair(name: "TempPair"),
            let privKeyData = Keygen.copyExternalRepresentation(key: keyPair.privateKey),
            let pubKeyData = Keygen.copyExternalRepresentation(key: keyPair.publicKey) {
            if let restoredKeyPair = Keygen.generateKeyPair(name: "TempPair", privateKeyData: privKeyData),
                let restoredPrivKeyData = Keygen.copyExternalRepresentation(key: restoredKeyPair.privateKey),
                let restoredPubKeyData = Keygen.copyExternalRepresentation(key: restoredKeyPair.publicKey) {
                XCTAssert(privKeyData.hex == restoredPrivKeyData.hex, "Mismatching private keys")
                XCTAssert(pubKeyData.hex == restoredPubKeyData.hex, "Mismatching public keys")
                
                let address = pubKeyData.sha256().sha256()
                let restoredAddress = restoredPubKeyData.sha256().sha256()
                XCTAssert(address == restoredAddress, "Mismatching addresses")
                
                let utxo = TransactionOutput(value: 100, address: address)
                let utxoHash = utxo.serialized().sha256()
                
                // Create a transaction and sign it, making sure first the sender has the right to claim the spendale outputs
                guard let signature = try? Keysign.sign(data: utxoHash, with: keyPair.privateKey) else {
                    XCTFail("Could not sign with original key")
                    return
                }
                guard let restoredSignature = try? Keysign.sign(data: utxoHash, with: restoredKeyPair.privateKey) else {
                    XCTFail("Could not sign with restored key")
                    return
                }
                let verified1 = Keysign.verify(publicKey: pubKeyData, data: utxoHash, signature: signature)
                let verified2 = Keysign.verify(publicKey: pubKeyData, data: utxoHash, signature: restoredSignature)
                let verified3 = Keysign.verify(publicKey: restoredPubKeyData, data: utxoHash, signature: restoredSignature)
                let verified4 = Keysign.verify(publicKey: restoredPubKeyData, data: utxoHash, signature: signature)
                XCTAssert(verified1 && verified2 && verified3 && verified4, "Original and restored keys are not fully interoperable")
            } else {
                XCTFail("Could not restore key pair")
            }
        } else {
            XCTFail("Could not generate key pair")
        }
    }
    
    func testWalletTxSigning() throws {
        let wallet1 = Wallet(name: "Wallet 1")!
        let wallet2 = Wallet(name: "Wallet 2")!
        
        let tx = Transaction.coinbase(address: wallet1.address, blockValue: 1)
        // Wallet 2 will try to steal all of Wallet 1's balance, which is here set to 100
        let wallet1utxo = UnspentTransaction(output: tx.outputs.first!, outpoint: TransactionOutputReference(hash: tx.txHash, index: 0))
        let originalOutputData = wallet1utxo.outpoint.hash

        // Create a transaction and sign it, making sure first the sender has the right to claim the spendale outputs
        let signature1 = try wallet1.sign(utxo: wallet1utxo)
        let signature2 = try wallet2.sign(utxo: wallet1utxo)
        let verified1 = Keysign.verify(publicKey: wallet1.publicKey, data: originalOutputData, signature: signature1)
        let verified2 = Keysign.verify(publicKey: wallet1.publicKey, data: originalOutputData, signature: signature2)
        XCTAssert(verified1, "Wallet1 should have been verified")
        XCTAssert(!verified2, "Wallet2 should not have been verified")
    }
    
    func testTransactions() throws {
        // Two wallets, one blockchain
        let wallet1 = Wallet(name: "Node1Wallet")!
        // Override central address
        NodeAddress.centralAddress = NodeAddress(host: "localhost", port: 1337)
        let node1 = Node(type: .central)
        let wallet2 = Wallet(name: "Node2Wallet")!
        let _ = try? node1.mineBlock(minerAddress: wallet1.address)
        
        // Wallet1 has mined genesis block, and should have gotten the reward
        XCTAssert(node1.blockchain.balance(for: wallet1.address) == node1.blockchain.currentBlockValue())
        // Wallet2 is broke
        XCTAssert(node1.blockchain.balance(for: wallet2.address) == 0)
        
        // Send 1000 from Wallet1 to Wallet2, and again let wallet1 mine the next block
        let _ = try node1.createTransaction(sender: wallet1, recipientAddress: wallet2.address, value: 1)
        XCTAssert(node1.mempool.count == 1) // One Tx should be in the pool, ready to go into the next block when mined
        let _ = try? node1.mineBlock(minerAddress: wallet1.address)
        XCTAssert(node1.mempool.count == 0) // Tx pool should now be clear
        
        // Wallet1 should now have a balance == two block rewards - 1000
        let node1Balance = node1.blockchain.balance(for: wallet1.address)
        let expetedNode1Balance = (node1.blockchain.currentBlockValue() * 2) - 1
        XCTAssert(node1Balance == expetedNode1Balance, "\(node1Balance) != \(expetedNode1Balance)")
        // Wallet 2 should have a balance == 1000
        let node2Balance = node1.blockchain.balance(for: wallet2.address)
        let expectedNode2Balance = 1
        XCTAssert(node2Balance == expectedNode2Balance, "\(node2Balance) != \(expectedNode2Balance)")
        
        // Attempt to send more from Wallet1 than it currently has, expect failure
        do {
            let _ = try node1.createTransaction(sender: wallet1, recipientAddress: wallet2.address, value: UInt64.max)
            XCTAssert(false, "Overdraft")
        } catch { }
        
        // Check sanity of utxo state, ensuring Wallet1 and Wallet2 has rights to their unspent outputs
        let utxosWallet1 = node1.blockchain.findSpendableOutputs(for: wallet1.address)
        let utxosWallet2 = node1.blockchain.findSpendableOutputs(for: wallet2.address)
        XCTAssert(wallet1.canUnlock(utxos: utxosWallet1.map { $0.output }))
        XCTAssert(!wallet1.canUnlock(utxos: utxosWallet2.map { $0.output }))
        XCTAssert(wallet2.canUnlock(utxos: utxosWallet2.map { $0.output }))
        XCTAssert(!wallet2.canUnlock(utxos: utxosWallet1.map { $0.output }))
    }
    
    func testNodeNetwork() {
        // Set up our network of 3 nodes, and letting the first node mine the genesis block
        // Excpect the genesis block to propagate to all nodes
        let initialSync = XCTestExpectation(description: "Initial sync")
        let node1Wallet = Wallet(name: "Node1Wallet")!
        // Override central address
        NodeAddress.centralAddress = NodeAddress(host: "localhost", port: 43210)
        let node1 = Node(type: .central)
        node1.connect()
        defer { node1.disconnect() }
        let _ = try? node1.mineBlock(minerAddress: node1Wallet.address)
        let node2Wallet = Wallet(name: "Node2Wallet")!
        let node2 = Node(type: .peer)
        node2.connect()
        defer { node2.disconnect() }
        let node3 = Node(type: .peer)
        node3.connect()
        defer { node3.disconnect() }
        DispatchQueue.global().async {
            while true {
                if node2.blockchain.blocks.count == 1 && node3.blockchain.blocks.count == 1 {
                    initialSync.fulfill()
                    break
                }
            }
        }
        wait(for: [initialSync], timeout: 5)
        
        // Now create a transaction on node1 - from node1's wallet to node'2s wallet
        // Expect everyone's mempool to update with the new transaction
        let txSync = XCTestExpectation(description: "Sync transactions")
        do {
            let _ = try node1.createTransaction(sender: node1Wallet, recipientAddress: node2Wallet.address, value: 1)
        } catch {
            XCTFail("Overdraft")
        }
        DispatchQueue.global().async {
            while true {
                let requirements = [
                    node1.mempool.count == node2.mempool.count,
                    node2.mempool.count == node3.mempool.count,
                    node3.mempool.count == 1
                ]
                if requirements.allSatisfy({ $0 == true}) {
                    txSync.fulfill()
                    break
                }
            }
        }
        wait(for: [txSync], timeout: 3)
        
        let newNodeTxSync = XCTestExpectation(description: "Sync new node")
        let node4 = Node(type: .peer)
        node4.connect()
        defer { node4.disconnect() }
        DispatchQueue.global().async {
            while true {
                let requirements = [
                    node4.mempool.count == node1.mempool.count,
                    node4.blockchain.blocks.count == node1.blockchain.blocks.count
                ]
                if requirements.allSatisfy({ $0 == true}) {
                    newNodeTxSync.fulfill()
                    break
                }
            }
        }
        wait(for: [newNodeTxSync], timeout: 5)
        
        // Now let node2 mine the next block, claiming the Coinbase reward as well as receiving 1 from the above transaction
        // Expect every node's blocks to update, and everyones utxos to update appropriately
        let mineSync = XCTestExpectation(description: "Mining sync")
        let _ = try? node2.mineBlock(minerAddress: node2Wallet.address)
        DispatchQueue.global().async {
            while true {
                let requirements = [
                    node1.blockchain.blocks.count == node2.blockchain.blocks.count,
                    node2.blockchain.blocks.count == node3.blockchain.blocks.count,
                    node3.blockchain.blocks.count == node4.blockchain.blocks.count,
                    node4.blockchain.blocks.count == 2,
                    
                    node1.blockchain.balance(for: node2Wallet.address) == node2.blockchain.balance(for: node2Wallet.address),
                    node2.blockchain.balance(for: node2Wallet.address) == node3.blockchain.balance(for: node2Wallet.address),
                    node3.blockchain.balance(for: node2Wallet.address) == node4.blockchain.balance(for: node2Wallet.address),
                    node1.blockchain.balance(for: node2Wallet.address) == node1.blockchain.currentBlockValue() + 1,
                    
                    node1.blockchain.balance(for: node1Wallet.address) == node1.blockchain.currentBlockValue() - 1,
                    node2.blockchain.balance(for: node1Wallet.address) == node2.blockchain.currentBlockValue() - 1,
                    node3.blockchain.balance(for: node1Wallet.address) == node3.blockchain.currentBlockValue() - 1,
                    node4.blockchain.balance(for: node1Wallet.address) == node4.blockchain.currentBlockValue() - 1
                ]
                if requirements.allSatisfy({ $0 == true}) {
                    mineSync.fulfill()
                    break
                }
            }
        }
        wait(for: [mineSync], timeout: 5)
    }
    
    func testNetworkPingPong() {
        let nw1 = MockNetwork.randomNetwork()
        let nw2 = MockNetwork.randomNetwork()
        defer {
            nw1.network.stop()
            nw2.network.stop()
        }

        nw1.network.send(command: .ping, payload: PingMessage(), to: NodeAddress(host: "127.0.0.1", port: nw2.port))
        let pingPongExp = XCTestExpectation(description: "(Network) Ping? PONG!")
        DispatchQueue.global().async {
            while true {
                if nw2.delegate.ping && nw1.delegate.pong {
                    pingPongExp.fulfill()
                    break
                }
            }
        }
        wait(for: [pingPongExp], timeout: 3)
        
        #if canImport(NIO)
        let nw3 = MockNetwork.randomNIO()
        let nw4 = MockNetwork.randomNIO()
        defer {
            nw3.network.stop()
            nw4.network.stop()
        }

        nw3.network.send(command: .ping, payload: PingMessage(), to: NodeAddress(host: "127.0.0.1", port: nw4.port))
        let pingPongExp2 = XCTestExpectation(description: "(NIO) Ping? PONG!")
        DispatchQueue.global().async {
            while true {
                if nw4.delegate.ping && nw3.delegate.pong {
                    pingPongExp2.fulfill()
                    break
                }
            }
        }
        wait(for: [pingPongExp2], timeout: 3)
        #endif
    }
    
    func testNodePingPongPrune() {
        Node.pingInterval = 3
        NodeAddress.centralAddress = NodeAddress(host: "localhost", port: 43210)
        let central = Node(type: .central)
        central.connect()
        defer { central.disconnect() }
        
        let peer1 = Node(type: .peer)
        peer1.connect()
        defer { peer1.disconnect() }

        let peer2 = Node(type: .peer)
        peer2.connect()

        let peerCountExp = XCTestExpectation(description: "Initial peers")
        DispatchQueue.global().async {
            while true {
                if central.peers.count == 2 {
                    peerCountExp.fulfill()
                    break
                }
            }
        }
        wait(for: [peerCountExp], timeout: Node.pingInterval)
        
        peer2.disconnect()
        let peerCountExp2 = XCTestExpectation(description: "Pruned peers")
        DispatchQueue.global().async {
            while true {
                if central.peers.count == 1 {
                    peerCountExp2.fulfill()
                    break
                }
            }
        }
        wait(for: [peerCountExp2], timeout: Node.pingInterval * 5)
    }
    
    func testNodeStatePersistence() {
        // Create a Node, mine a block, and add a transaction - then persist it's state
        let node = Node()
        let wallet = Wallet(name: "Wallet")!
        let _ = try? node.mineBlock(minerAddress: wallet.address)
        let _ = try? node.createTransaction(sender: wallet, recipientAddress: wallet.address, value: 1000)
        node.saveState()
        let state = Node.loadState()
        guard
            let stateBlockCount = state.blockchain?.blocks.count,
            let stateMempoolCount = state.mempool?.count
            else {
                XCTFail("State load failed")
                return
        }
        XCTAssert(stateBlockCount == node.blockchain.blocks.count)
        XCTAssert(stateMempoolCount == node.mempool.count)
        node.clearState()
    }
    
    func testCirculatingSupply() {
        let blockchain = Blockchain()
        XCTAssert(blockchain.circulatingSupply() == 0)
        (1...1_000_000).forEach { i in
            let block = Block(timestamp: 0, transactions: [Transaction.coinbase(address: Data(), blockValue: blockchain.currentBlockValue())], nonce: 0, hash: Data(), previousHash: Data())
            blockchain.blocks.append(block)
        }
        let expectedCirculatingSupply =
            blockchain.blocks
                .map { $0.transactions.first! }
                .map { $0.outputs.first!.value }
                .reduce(0, +)
        XCTAssert(expectedCirculatingSupply == blockchain.circulatingSupply())
    }
    
    
    static let allTests = [
        ("testKeyGenAndTxSigning", testKeyGenAndTxSigning),
        ("testKeyRestoreData", testKeyRestoreData),
        ("testKeyRestoreHex", testKeyRestoreHex),
        ("testWalletStore", testWalletStore),
        ("testWalletFromKeychainAndTxSigning", testWalletFromKeychainAndTxSigning),
        ("testKeyRestoreFromDataAndTxSigning", testKeyRestoreFromDataAndTxSigning),
        ("testWalletTxSigning", testWalletTxSigning),
        ("testTransactions", testTransactions),
        ("testNodeNetwork", testNodeNetwork),
        ("testNetworkPingPong", testNetworkPingPong),
        ("testNodePingPongPrune", testNodePingPongPrune),
        ("testNodeStatePersistence", testNodeStatePersistence),
        ("testCirculatingSupply", testCirculatingSupply)
    ]
    
}

