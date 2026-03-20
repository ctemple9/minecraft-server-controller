import Foundation

// MARK: - Data helpers

extension Data {
    mutating func appendUInt16BE(_ value: UInt16) {
        let hi = UInt8((value >> 8) & 0xFF)
        let lo = UInt8(value & 0xFF)
        append(hi)
        append(lo)
    }

    mutating func appendUInt64BE(_ value: UInt64) {
        append(UInt8((value >> 56) & 0xFF))
        append(UInt8((value >> 48) & 0xFF))
        append(UInt8((value >> 40) & 0xFF))
        append(UInt8((value >> 32) & 0xFF))
        append(UInt8((value >> 24) & 0xFF))
        append(UInt8((value >> 16) & 0xFF))
        append(UInt8((value >> 8) & 0xFF))
        append(UInt8(value & 0xFF))
    }

    func readUInt16BE(at index: Int) -> UInt16 {
        let b0 = UInt16(self[index])
        let b1 = UInt16(self[index + 1])
        return (b0 << 8) | b1
    }

    func readUInt64BE(at index: Int) -> UInt64 {
        var v: UInt64 = 0
        v |= UInt64(self[index]) << 56
        v |= UInt64(self[index + 1]) << 48
        v |= UInt64(self[index + 2]) << 40
        v |= UInt64(self[index + 3]) << 32
        v |= UInt64(self[index + 4]) << 24
        v |= UInt64(self[index + 5]) << 16
        v |= UInt64(self[index + 6]) << 8
        v |= UInt64(self[index + 7])
        return v
    }
}

// MARK: - SHA1 (pure Swift, minimal)

enum SHA1 {
    static func hash(_ data: Data) -> [UInt8] {
        var message = [UInt8](data)

        let ml = UInt64(message.count) * 8

        message.append(0x80)

        while (message.count % 64) != 56 {
            message.append(0x00)
        }

        message.append(UInt8((ml >> 56) & 0xFF))
        message.append(UInt8((ml >> 48) & 0xFF))
        message.append(UInt8((ml >> 40) & 0xFF))
        message.append(UInt8((ml >> 32) & 0xFF))
        message.append(UInt8((ml >> 24) & 0xFF))
        message.append(UInt8((ml >> 16) & 0xFF))
        message.append(UInt8((ml >> 8) & 0xFF))
        message.append(UInt8(ml & 0xFF))

        var h0: UInt32 = 0x67452301
        var h1: UInt32 = 0xEFCDAB89
        var h2: UInt32 = 0x98BADCFE
        var h3: UInt32 = 0x10325476
        var h4: UInt32 = 0xC3D2E1F0

        var w = [UInt32](repeating: 0, count: 80)

        for chunkStart in stride(from: 0, to: message.count, by: 64) {
            for i in 0..<16 {
                let j = chunkStart + i * 4
                let b0 = UInt32(message[j]) << 24
                let b1 = UInt32(message[j + 1]) << 16
                let b2 = UInt32(message[j + 2]) << 8
                let b3 = UInt32(message[j + 3])
                w[i] = b0 | b1 | b2 | b3
            }

            for i in 16..<80 {
                let v = w[i - 3] ^ w[i - 8] ^ w[i - 14] ^ w[i - 16]
                w[i] = leftRotate(v, by: 1)
            }

            var a = h0
            var b = h1
            var c = h2
            var d = h3
            var e = h4

            for i in 0..<80 {
                var f: UInt32 = 0
                var k: UInt32 = 0

                switch i {
                case 0...19:
                    f = (b & c) | ((~b) & d)
                    k = 0x5A827999
                case 20...39:
                    f = b ^ c ^ d
                    k = 0x6ED9EBA1
                case 40...59:
                    f = (b & c) | (b & d) | (c & d)
                    k = 0x8F1BBCDC
                default:
                    f = b ^ c ^ d
                    k = 0xCA62C1D6
                }

                let temp = leftRotate(a, by: 5) &+ f &+ e &+ k &+ w[i]
                e = d
                d = c
                c = leftRotate(b, by: 30)
                b = a
                a = temp
            }

            h0 = h0 &+ a
            h1 = h1 &+ b
            h2 = h2 &+ c
            h3 = h3 &+ d
            h4 = h4 &+ e
        }

        var digest = [UInt8]()
        digest.reserveCapacity(20)

        for h in [h0, h1, h2, h3, h4] {
            digest.append(UInt8((h >> 24) & 0xFF))
            digest.append(UInt8((h >> 16) & 0xFF))
            digest.append(UInt8((h >> 8) & 0xFF))
            digest.append(UInt8(h & 0xFF))
        }

        return digest
    }

    private static func leftRotate(_ x: UInt32, by: UInt32) -> UInt32 {
        return (x << by) | (x >> (32 - by))
    }
}

