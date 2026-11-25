// SPDX-License-Identifier: AGPL-3.0-only

namespace CouchSubs.Core.Tests;

/// <summary>
/// Denemeler için küçük temel (baseline) JPEG çözücü: testdata/frames karelerini (Huffman, 8 bit, YCbCr, her örnekleme)
/// BGRA <see cref="Frame"/>'e açar. .NET'in Mac'te JPEG çözücüsü yok; deneme projesine paket eklenmesin diye elle yazıldı.
/// Renk alt örneklemesi en yakın noktayla büyütülür (Apple'ın çözücüsünden bir iki ton farklı olabilir).
/// </summary>
internal static class Jpeg
{
    private static readonly int[] ZigZag =
    [
        0, 1, 8, 16, 9, 2, 3, 10, 17, 24, 32, 25, 18, 11, 4, 5, 12, 19, 26, 33, 40, 48, 41, 34, 27, 20, 13, 6, 7, 14, 21, 28,
        35, 42, 49, 56, 57, 50, 43, 36, 29, 22, 15, 23, 30, 37, 44, 51, 58, 59, 52, 45, 38, 31, 39, 46, 53, 60, 61, 54, 47, 55,
        62, 63,
    ];

    private sealed class Huffman
    {
        public readonly Dictionary<(int Length, int Code), byte> Codes = [];
    }

    private sealed class Component
    {
        public int Id, H, V, Quant, Dc, Ac, Pred;
        public int BlocksW, BlocksH;
        public byte[] Plane = [];
    }

    public static Frame Load(string path)
    {
        var data = File.ReadAllBytes(path);
        var quant = new int[4][];
        var dcTables = new Huffman[4];
        var acTables = new Huffman[4];
        var components = new List<Component>();
        int width = 0, height = 0, restart = 0, at = 2;
        while (at < data.Length)
        {
            if (data[at] != 0xFF) { at++; continue; }
            var marker = data[at + 1];
            at += 2;
            if (marker is 0xD8 or 0x01 or (>= 0xD0 and <= 0xD7)) continue;
            if (marker == 0xD9) break;
            var length = (data[at] << 8) | data[at + 1];
            var segment = at + 2;
            switch (marker)
            {
                case 0xDB:
                    for (var p = segment; p < at + length;)
                    {
                        var precision = data[p] >> 4;
                        var id = data[p] & 15;
                        p++;
                        quant[id] = new int[64];
                        for (var k = 0; k < 64; k++)
                        {
                            quant[id][k] = precision == 0 ? data[p] : (data[p] << 8) | data[p + 1];
                            p += precision == 0 ? 1 : 2;
                        }
                    }
                    break;
                case 0xC4:
                    for (var p = segment; p < at + length;)
                    {
                        var kind = data[p] >> 4;
                        var id = data[p] & 15;
                        var counts = new int[16];
                        for (var k = 0; k < 16; k++) counts[k] = data[p + 1 + k];
                        p += 17;
                        var table = new Huffman();
                        var code = 0;
                        for (var len = 1; len <= 16; len++)
                        {
                            for (var k = 0; k < counts[len - 1]; k++) table.Codes[(len, code++)] = data[p++];
                            code <<= 1;
                        }
                        if (kind == 0) dcTables[id] = table; else acTables[id] = table;
                    }
                    break;
                case 0xC0:
                case 0xC1:
                    height = (data[segment + 1] << 8) | data[segment + 2];
                    width = (data[segment + 3] << 8) | data[segment + 4];
                    for (var k = 0; k < data[segment + 5]; k++)
                    {
                        var p = segment + 6 + (k * 3);
                        components.Add(new Component { Id = data[p], H = data[p + 1] >> 4, V = data[p + 1] & 15, Quant = data[p + 2] });
                    }
                    break;
                case 0xC2:
                    throw new NotSupportedException("progressive JPEG");
                case 0xDD:
                    restart = (data[segment] << 8) | data[segment + 1];
                    break;
                case 0xDA:
                    var count = data[segment];
                    for (var k = 0; k < count; k++)
                    {
                        var c = components.First(item => item.Id == data[segment + 1 + (k * 2)]);
                        c.Dc = data[segment + 2 + (k * 2)] >> 4;
                        c.Ac = data[segment + 2 + (k * 2)] & 15;
                    }
                    at = Decode(data, at + length, width, height, components, quant, dcTables, acTables, restart);
                    return ToFrame(width, height, components);
            }
            at += length;
        }
        throw new InvalidDataException("JPEG taraması yok: " + path);
    }

    private static int Decode(byte[] data, int at, int width, int height, List<Component> components, int[][] quant,
                              Huffman[] dcTables, Huffman[] acTables, int restart)
    {
        int hMax = components.Max(c => c.H), vMax = components.Max(c => c.V);
        int mcuW = 8 * hMax, mcuH = 8 * vMax;
        int mcusX = (width + mcuW - 1) / mcuW, mcusY = (height + mcuH - 1) / mcuH;
        foreach (var c in components)
        {
            c.BlocksW = mcusX * c.H;
            c.BlocksH = mcusY * c.V;
            c.Plane = new byte[c.BlocksW * 8 * c.BlocksH * 8];
        }
        int bits = 0, bitCount = 0, p = at;
        int Bit()
        {
            if (bitCount == 0)
            {
                if (p >= data.Length) return 0;
                bits = data[p++];
                if (bits == 0xFF)
                {
                    var next = data[p];
                    if (next == 0) p++;
                    else if (next is >= 0xD0 and <= 0xD7) { p--; bits = 0; }
                }
                bitCount = 8;
            }
            bitCount--;
            return (bits >> bitCount) & 1;
        }
        int Receive(int n)
        {
            var v = 0;
            for (var i = 0; i < n; i++) v = (v << 1) | Bit();
            return v;
        }
        static int Extend(int v, int n) => n == 0 ? 0 : v < (1 << (n - 1)) ? v - (1 << n) + 1 : v;
        byte DecodeSymbol(Huffman table)
        {
            var code = 0;
            for (var len = 1; len <= 16; len++)
            {
                code = (code << 1) | Bit();
                if (table.Codes.TryGetValue((len, code), out var symbol)) return symbol;
            }
            return 0;
        }
        var block = new int[64];
        var output = new double[64];
        var mcu = 0;
        for (var my = 0; my < mcusY; my++)
        {
            for (var mx = 0; mx < mcusX; mx++)
            {
                if (restart > 0 && mcu > 0 && mcu % restart == 0)
                {
                    // Yeniden başlama imi: bit akışı bayta hizalanır, öngörüler sıfırlanır.
                    bitCount = 0;
                    while (p + 1 < data.Length && !(data[p] == 0xFF && data[p + 1] is >= 0xD0 and <= 0xD7)) p++;
                    p += 2;
                    foreach (var c in components) c.Pred = 0;
                }
                mcu++;
                foreach (var c in components)
                {
                    var q = quant[c.Quant];
                    for (var by = 0; by < c.V; by++)
                        for (var bx = 0; bx < c.H; bx++)
                        {
                            Array.Clear(block);
                            var t = DecodeSymbol(dcTables[c.Dc]);
                            c.Pred += Extend(Receive(t), t);
                            block[0] = c.Pred * q[0];
                            for (var k = 1; k < 64;)
                            {
                                var rs = DecodeSymbol(acTables[c.Ac]);
                                int r = rs >> 4, s = rs & 15;
                                if (s == 0)
                                {
                                    if (r == 15) { k += 16; continue; }
                                    break;
                                }
                                k += r;
                                if (k > 63) break;
                                block[ZigZag[k]] = Extend(Receive(s), s) * q[k];
                                k++;
                            }
                            Idct(block, output);
                            int ox = ((mx * c.H) + bx) * 8, oy = ((my * c.V) + by) * 8, stride = c.BlocksW * 8;
                            for (var y = 0; y < 8; y++)
                                for (var x = 0; x < 8; x++)
                                    c.Plane[((oy + y) * stride) + ox + x] = (byte)Math.Clamp((int)Math.Round(output[(y * 8) + x] + 128), 0, 255);
                        }
                }
            }
        }
        return p;
    }

    private static readonly double[,] Cosines = BuildCosines();

    private static double[,] BuildCosines()
    {
        var table = new double[8, 8];
        for (var x = 0; x < 8; x++)
            for (var u = 0; u < 8; u++)
                table[x, u] = (u == 0 ? Math.Sqrt(0.5) : 1) * Math.Cos(((2 * x) + 1) * u * Math.PI / 16);
        return table;
    }

    private static void Idct(int[] block, double[] output)
    {
        var rows = new double[64];
        for (var y = 0; y < 8; y++)
            for (var x = 0; x < 8; x++)
            {
                double sum = 0;
                for (var u = 0; u < 8; u++) sum += Cosines[x, u] * block[(y * 8) + u];
                rows[(y * 8) + x] = sum / 2;
            }
        for (var x = 0; x < 8; x++)
            for (var y = 0; y < 8; y++)
            {
                double sum = 0;
                for (var v = 0; v < 8; v++) sum += Cosines[y, v] * rows[(v * 8) + x];
                output[(y * 8) + x] = sum / 2;
            }
    }

    private static Frame ToFrame(int width, int height, List<Component> components)
    {
        int hMax = components.Max(c => c.H), vMax = components.Max(c => c.V);
        var pixels = new byte[width * height * 4];
        int Sample(Component c, int x, int y) => c.Plane[(y * c.V / vMax * c.BlocksW * 8) + (x * c.H / hMax)];
        for (var y = 0; y < height; y++)
            for (var x = 0; x < width; x++)
            {
                var o = ((y * width) + x) * 4;
                if (components.Count < 3)
                {
                    var g = (byte)Sample(components[0], x, y);
                    pixels[o] = pixels[o + 1] = pixels[o + 2] = g;
                }
                else
                {
                    double luma = Sample(components[0], x, y), cb = Sample(components[1], x, y) - 128, cr = Sample(components[2], x, y) - 128;
                    pixels[o + 2] = (byte)Math.Clamp((int)Math.Round(luma + (1.402 * cr)), 0, 255);
                    pixels[o + 1] = (byte)Math.Clamp((int)Math.Round(luma - (0.344136 * cb) - (0.714136 * cr)), 0, 255);
                    pixels[o] = (byte)Math.Clamp((int)Math.Round(luma + (1.772 * cb)), 0, 255);
                }
                pixels[o + 3] = 255;
            }
        return new Frame(pixels, width, height, width * 4);
    }
}
