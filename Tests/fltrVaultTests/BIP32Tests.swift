//===----------------------------------------------------------------------===//
//
// This source file is part of the fltrVault open source project
//
// Copyright (c) 2022 fltrWallet AG and the fltrVault project authors
// Licensed under Apache License v2.0
//
// See LICENSE.md for license information
//
// SPDX-License-Identifier: Apache-2.0
//
//===----------------------------------------------------------------------===//
import fltrECC
import fltrTx
@testable import fltrVault
import XCTest

final class BIP32Tests: XCTestCase {
    func evolution(current path: inout HD.Path,
                   tail: HD.ChildNumber,
                   root: inout HD.FullNode?,
                   child: inout HD.FullNode?,
                   public xPub: String,
                   private xPrv: String) {
        path = path + [ tail ]
        child = try? child?.makeChildNode(for: path).last
        XCTAssertEqual(child?.serialize(for: .bip44, network: .main),
                       try? root?.makeChildNode(for: path).last?.serialize(for: .bip44, network: .main))
        XCTAssertEqual(child?.serialize(for: .bip44, network: .main), xPrv)
        let neutered = child?.neuter()
        XCTAssertEqual(neutered?.serialize(for: .bip44, network: .main), xPub)
        
        precondition(path.last == tail)
    }
    
    func testVector1() {
        // m
        let seed = HD.Seed.seed(from: "000102030405060708090a0b0c0d0e0f".hex2Bytes)
        var root = HD.FullNode(seed)
        XCTAssertEqual(root?.serialize(for: .bip44, network: .main),
                       "xprv9s21ZrQH143K3QTDL4LXw2F7HEK3wJUD2nW2nRk4stbPy6cq3jPPqjiChkVvvNKmPGJxWUtg6LnF5kejMRNNU3TGtRBeJgk33yuGBxrMPHi")
        let neutered = root?.neuter()
        XCTAssertEqual(neutered?.serialize(for: .bip44, network: .main),
                       "xpub661MyMwAqRbcFtXgS5sYJABqqG9YLmC4Q1Rdap9gSE8NqtwybGhePY2gZ29ESFjqJoCu1Rupje8YtGqsefD265TMg7usUDFdp6W1EGMcet8")
        var child = root
        var path: HD.Path = .empty

        
        // m/0'
        self.evolution(current: &path,
                       tail: .hardened(0),
                       root: &root,
                       child: &child,
                       public: "xpub68Gmy5EdvgibQVfPdqkBBCHxA5htiqg55crXYuXoQRKfDBFA1WEjWgP6LHhwBZeNK1VTsfTFUHCdrfp1bgwQ9xv5ski8PX9rL2dZXvgGDnw",
                       private: "xprv9uHRZZhk6KAJC1avXpDAp4MDc3sQKNxDiPvvkX8Br5ngLNv1TxvUxt4cV1rGL5hj6KCesnDYUhd7oWgT11eZG7XnxHrnYeSvkzY7d2bhkJ7")
        
        // m/0'/1
        self.evolution(current: &path,
                       tail: .normal(1),
                       root: &root,
                       child: &child,
                       public: "xpub6ASuArnXKPbfEwhqN6e3mwBcDTgzisQN1wXN9BJcM47sSikHjJf3UFHKkNAWbWMiGj7Wf5uMash7SyYq527Hqck2AxYysAA7xmALppuCkwQ",
                       private: "xprv9wTYmMFdV23N2TdNG573QoEsfRrWKQgWeibmLntzniatZvR9BmLnvSxqu53Kw1UmYPxLgboyZQaXwTCg8MSY3H2EU4pWcQDnRnrVA1xe8fs")
        
        // m/0'/1/2'
        self.evolution(current: &path,
                       tail: .hardened(2),
                       root: &root,
                       child: &child,
                       public: "xpub6D4BDPcP2GT577Vvch3R8wDkScZWzQzMMUm3PWbmWvVJrZwQY4VUNgqFJPMM3No2dFDFGTsxxpG5uJh7n7epu4trkrX7x7DogT5Uv6fcLW5",
                       private: "xprv9z4pot5VBttmtdRTWfWQmoH1taj2axGVzFqSb8C9xaxKymcFzXBDptWmT7FwuEzG3ryjH4ktypQSAewRiNMjANTtpgP4mLTj34bhnZX7UiM")
        
        // m/0'/1/2'/2
        self.evolution(current: &path,
                       tail: .normal(2),
                       root: &root,
                       child: &child,
                       public: "xpub6FHa3pjLCk84BayeJxFW2SP4XRrFd1JYnxeLeU8EqN3vDfZmbqBqaGJAyiLjTAwm6ZLRQUMv1ZACTj37sR62cfN7fe5JnJ7dh8zL4fiyLHV",
                       private: "xprvA2JDeKCSNNZky6uBCviVfJSKyQ1mDYahRjijr5idH2WwLsEd4Hsb2Tyh8RfQMuPh7f7RtyzTtdrbdqqsunu5Mm3wDvUAKRHSC34sJ7in334")
        
        // m/0'/1/2'/2/1000000000
        self.evolution(current: &path,
                       tail: .normal(1_000_000_000),
                       root: &root,
                       child: &child,
                       public: "xpub6H1LXWLaKsWFhvm6RVpEL9P4KfRZSW7abD2ttkWP3SSQvnyA8FSVqNTEcYFgJS2UaFcxupHiYkro49S8yGasTvXEYBVPamhGW6cFJodrTHy",
                       private: "xprvA41z7zogVVwxVSgdKUHDy1SKmdb533PjDz7J6N6mV6uS3ze1ai8FHa8kmHScGpWmj4WggLyQjgPie1rFSruoUihUZREPSL39UNdE3BBDu76")
    }

    func testVector2() {
        // m
        let seed = HD.Seed.seed(from: "fffcf9f6f3f0edeae7e4e1dedbd8d5d2cfccc9c6c3c0bdbab7b4b1aeaba8a5a29f9c999693908d8a8784817e7b7875726f6c696663605d5a5754514e4b484542".hex2Bytes)
        var root = HD.FullNode(seed)
        XCTAssertEqual(root?.serialize(for: .bip44, network: .main),
                       "xprv9s21ZrQH143K31xYSDQpPDxsXRTUcvj2iNHm5NUtrGiGG5e2DtALGdso3pGz6ssrdK4PFmM8NSpSBHNqPqm55Qn3LqFtT2emdEXVYsCzC2U")
        let neutered = root?.neuter()
        XCTAssertEqual(neutered?.serialize(for: .bip44, network: .main),
                       "xpub661MyMwAqRbcFW31YEwpkMuc5THy2PSt5bDMsktWQcFF8syAmRUapSCGu8ED9W6oDMSgv6Zz8idoc4a6mr8BDzTJY47LJhkJ8UB7WEGuduB")
        var child = root
        var path: HD.Path = .empty

        // m/0
        self.evolution(current: &path,
                       tail: .normal(0),
                       root: &root,
                       child: &child,
                       public: "xpub69H7F5d8KSRgmmdJg2KhpAK8SR3DjMwAdkxj3ZuxV27CprR9LgpeyGmXUbC6wb7ERfvrnKZjXoUmmDznezpbZb7ap6r1D3tgFxHmwMkQTPH",
                       private: "xprv9vHkqa6EV4sPZHYqZznhT2NPtPCjKuDKGY38FBWLvgaDx45zo9WQRUT3dKYnjwih2yJD9mkrocEZXo1ex8G81dwSM1fwqWpWkeS3v86pgKt")
        
        // m/0/2147483647'
        self.evolution(current: &path,
                       tail: .hardened(2_147_483_647),
                       root: &root,
                       child: &child,
                       public: "xpub6ASAVgeehLbnwdqV6UKMHVzgqAG8Gr6riv3Fxxpj8ksbH9ebxaEyBLZ85ySDhKiLDBrQSARLq1uNRts8RuJiHjaDMBU4Zn9h8LZNnBC5y4a",
                       private: "xprv9wSp6B7kry3Vj9m1zSnLvN3xH8RdsPP1Mh7fAaR7aRLcQMKTR2vidYEeEg2mUCTAwCd6vnxVrcjfy2kRgVsFawNzmjuHc2YmYRmagcEPdU9")

        // m/0/2147483647'/1
        self.evolution(current: &path,
                       tail: .normal(1),
                       root: &root,
                       child: &child,
                       public: "xpub6DF8uhdarytz3FWdA8TvFSvvAh8dP3283MY7p2V4SeE2wyWmG5mg5EwVvmdMVCQcoNJxGoWaU9DCWh89LojfZ537wTfunKau47EL2dhHKon",
                       private: "xprv9zFnWC6h2cLgpmSA46vutJzBcfJ8yaJGg8cX1e5StJh45BBciYTRXSd25UEPVuesF9yog62tGAQtHjXajPPdbRCHuWS6T8XA2ECKADdw4Ef")

        // m/0/2147483647'/1/2147483646'
        self.evolution(current: &path,
                       tail: .hardened(2_147_483_646),
                       root: &root,
                       child: &child,
                       public: "xpub6ERApfZwUNrhLCkDtcHTcxd75RbzS1ed54G1LkBUHQVHQKqhMkhgbmJbZRkrgZw4koxb5JaHWkY4ALHY2grBGRjaDMzQLcgJvLJuZZvRcEL",
                       private: "xprvA1RpRA33e1JQ7ifknakTFpgNXPmW2YvmhqLQYMmrj4xJXXWYpDPS3xz7iAxn8L39njGVyuoseXzU6rcxFLJ8HFsTjSyQbLYnMpCqE2VbFWc")

        // m/0/2147483647'/1/2147483646'/2
        self.evolution(current: &path,
                       tail: .normal(2),
                       root: &root,
                       child: &child,
                       public: "xpub6FnCn6nSzZAw5Tw7cgR9bi15UV96gLZhjDstkXXxvCLsUXBGXPdSnLFbdpq8p9HmGsApME5hQTZ3emM2rnY5agb9rXpVGyy3bdW6EEgAtqt",
                       private: "xprvA2nrNbFZABcdryreWet9Ea4LvTJcGsqrMzxHx98MMrotbir7yrKCEXw7nadnHM8Dq38EGfSh6dqA9QWTyefMLEcBYJUuekgW4BYPJcr9E7j")
    }
    
    func testVector3() {
        let seed = HD.Seed.seed(from: "4b381541583be4423346c643850da4b320e46a87ae3d2a4e6da11eba819cd4acba45d239319ac14f863b8d5ab5a0d0c64d2e8a1e7d1457df2e5a3c51c73235be"
            .hex2Bytes)
        var root = HD.FullNode(seed)
        XCTAssertEqual(root?.serialize(for: .bip44, network: .main),
                       "xprv9s21ZrQH143K25QhxbucbDDuQ4naNntJRi4KUfWT7xo4EKsHt2QJDu7KXp1A3u7Bi1j8ph3EGsZ9Xvz9dGuVrtHHs7pXeTzjuxBrCmmhgC6")
        let neutered = root?.neuter()
        XCTAssertEqual(neutered?.serialize(for: .bip44, network: .main),
                       "xpub661MyMwAqRbcEZVB4dScxMAdx6d4nFc9nvyvH3v4gJL378CSRZiYmhRoP7mBy6gSPSCYk6SzXPTf3ND1cZAceL7SfJ1Z3GC8vBgp2epUt13")
        var child = root
        var path: HD.Path = .empty
        
        // m/0'
        self.evolution(current: &path,
                       tail: .hardened(0),
                       root: &root,
                       child: &child,
                       public: "xpub68NZiKmJWnxxS6aaHmn81bvJeTESw724CRDs6HbuccFQN9Ku14VQrADWgqbhhTHBaohPX4CjNLf9fq9MYo6oDaPPLPxSb7gwQN3ih19Zm4Y",
                       private: "xprv9uPDJpEQgRQfDcW7BkF7eTya6RPxXeJCqCJGHuCJ4GiRVLzkTXBAJMu2qaMWPrS7AANYqdq6vcBcBUdJCVVFceUvJFjaPdGZ2y9WACViL4L")
    }
    
    func testFailHDPath() {
        let seed = HD.Seed.seed(size: 16)
        var root = HD.FullNode(seed)
        
        XCTAssertThrowsError(try root?.makeChildNode(for: [ .normal(1), .master ]))
        XCTAssertNoThrow(try root?.makeChildNode(for: [ .normal(1), .hardened(2) ]))

        // TODO: Should handle paths better and accept .master prefix
//        XCTAssertNoThrow(try root?.makeChildNode(for: [ .master, .normal(1) ]))
        var neutered = root?.neuter()
        XCTAssertThrowsError(try neutered?.makeChildNode(for: [ .normal(1), .master ]))
        XCTAssertThrowsError(try neutered?.makeChildNode(for: [ .normal(1), .hardened(2) ]))
    }
    

    func testBip32WebWallet() {
        let bip32WalletBasePath: HD.Path = [ .hardened(123) ]
        let seedBytes: [UInt8] = "4b381541583be4423346c643850da4b320e46a87ae3d2a4e6da11eba819cd4acba45d239319ac14f863b8d5ab5a0d0c64d2e8a1e7d1457df2e5a3c51c73235be"
            .hex2Bytes
        let seed = HD.Seed.seed(from: seedBytes)

        let bip32WalletExternalVectors: [String] = [
            "18B8RE4ynoGDpZ2Z7GiF5Z7X3RHtUF2kDp",
            "19AKi74CDpnQEiNvueRBUjJ2EtorbaNm6e",
            "1GwDs1RgjCNE2NhSa4NLYGdoPyAXGxm1Qf",
            "1FefJSteeRRqFfxpX8tLjJRQxAEVpZckfe",
            "1HTjaBHA5GwgMCJqTrYUJ8dBH48tqVm7tR",
        ]
        
        let bip32WalletChangeVectors: [String] = [
            "1GPq9aiJRVPL2YMKY1LnhuPzoQNmmCgS1s",
            "1Nhhzc92VVxRJUwmXxQF7kvsoqY56ro1N6",
            "1DvY1M5LrbEWtS3AZcQoEu1k3f1Ay4iYcF",
            "18nJ5MR6vbdPVPMSHpup4HQxxmHibsAhcS",
            "13ZXGxRme8mqAnxafXv5w3QmMszZRKAhEh",
        ]

        var rootNode = HD.FullNode(seed)!
        var addressNode: HD.NeuteredNode!
        var changeNode: HD.NeuteredNode!
        XCTAssertNoThrow(
            addressNode = try rootNode.makeChildNode(for: bip32WalletBasePath + [ .normal(0) ]).last!.neuter()
        )
        XCTAssertNoThrow(
            changeNode = try rootNode.makeChildNode(for: bip32WalletBasePath + [ .normal(1) ]).last!.neuter()
        )
        
        XCTAssertNoThrow(
            XCTAssertEqual(try rootNode.makeChildNode(for: bip32WalletBasePath).last!.serialize(for: .bip44, network: .main), "xprv9uPDJpEQgRQkbJWSLmAqLb254QBLkVvj5qVeqrb2vZF512w6HNKaKa5qbonLGXjscJ9N84tG1GPc75XMEsF8MV8QcP5BBwqa3b8uBsDzL9K")
        )

        for (index, address) in bip32WalletExternalVectors.enumerated() {
            XCTAssertEqual(
                PublicKeyHash(
                    DSA.PublicKey(
                        addressNode.childKey(path: bip32WalletBasePath + [ .normal(0), .normal(UInt32(index)) ])
                        .key.public
                    )
                    
                )
                .addressLegacyPKH(.main),
                address
            )
        }
        
        for (index, change) in bip32WalletChangeVectors.enumerated() {
            XCTAssertEqual(
                PublicKeyHash(
                    DSA.PublicKey(
                        changeNode.childKey(path: bip32WalletBasePath + [ .normal(1), .normal(UInt32(index)) ])
                            .key.public
                    )
                        
                )
                .addressLegacyPKH(.main),
                change
            )
        }
    }
}
