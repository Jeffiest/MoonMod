// Elden Ring reference animations for the animation editor (tools/anim/editor, its Reference panel).
//
//   ErReference extract <ELDEN RING\Game> <keys folder> <cache> [repository folder...]
//       Reads the player's skeleton and the game's own player animations (chr/c0000.anibnd.dcx,
//       chr/c0000_a00_hi.anibnd.dcx and the weapon movesets, chr/c0000_a0x ... a9x.anibnd.dcx) out of the install's
//       archives into <cache>, a folder per animation table (a000, a030, ...). The keys folder holds the archives'
//       public keys (DSAnimStudio's Res/PEM/ER); the Oodle library comes from the game folder. Writes the cache's
//       reference.json for the editor: this program's path and the repositories (folders of .hkx files, retargeted
//       onto the player's skeleton) to list beside the game's own.
//   ErReference decode <cache> <animation.hkx> <out.json>
//       Decodes one animation, the game's or one from a downloaded repository retargeted onto the player's skeleton,
//       into frames the editor draws: every bone's model-space position and local rotation per frame, and the root
//       motion.
//
// Everything it writes goes to the cache, which lives outside the repository: these are FromSoftware's files and
// stay on the player's machine.

using System.Numerics;
using System.Text;
using Org.BouncyCastle.Crypto;
using Org.BouncyCastle.Crypto.Engines;
using Org.BouncyCastle.OpenSsl;
using SoulsAssetPipeline.Animation;
using SoulsFormats;

static class ErReference
{
    static int Main(string[] args)
    {
        try
        {
            if (args.Length >= 4 && args[0] == "extract") return Extract(args[1], args[2], args[3], args[4..]);
            if (args.Length == 4 && args[0] == "decode") return Decode(args[1], args[2], args[3]);
        }
        catch (Exception e)
        {
            Console.Error.WriteLine(e.Message);
            return 1;
        }
        Console.Error.WriteLine("usage: ErReference extract <ELDEN RING\\Game> <keys folder> <cache> [repository folder...]\n" +
                                "       ErReference decode <cache> <animation.hkx> <out.json>");
        return 2;
    }

    // ---- extract ----------------------------------------------------------------------------------------------

    static int Extract(string game, string keys, string cache, string[] repositories)
    {
        System.Runtime.InteropServices.NativeLibrary.Load(Path.Combine(game, "oo2core_6_win64.dll"));
        var wanted = new Dictionary<ulong, string>
        {
            [PathHash("/chr/c0000.anibnd.dcx")] = "c0000.anibnd",
            [PathHash("/chr/c0000_a00_hi.anibnd.dcx")] = "c0000_a00_hi.anibnd",
        };
        // The weapon movesets and the rest of the player's animations, by tens of the animation table.
        for (int tens = 0; tens < 10; tens++)
            wanted[PathHash($"/chr/c0000_a{tens}x.anibnd.dcx")] = $"c0000_a{tens}x.anibnd";
        var found = new Dictionary<string, BND4>();
        foreach (var archive in new[] { "Data0", "Data1", "Data2", "Data3" })
        {
            var bhd = BHD5.Read(DecryptHeader(Path.Combine(game, archive + ".bhd"), Path.Combine(keys, archive.ToLowerInvariant() + ".pem")),
                                BHD5.Game.EldenRing);
            using var bdt = File.OpenRead(Path.Combine(game, archive + ".bdt"));
            foreach (var file in bhd.Buckets.SelectMany(b => b))
                if (wanted.TryGetValue(file.FileNameHash, out var name))
                    found[name] = BND4.Read(DCX.Decompress(file.ReadFile(bdt)));
        }
        if (!found.TryGetValue("c0000.anibnd", out var main))
            throw new Exception("chr/c0000.anibnd.dcx is not in this install's archives");

        Directory.CreateDirectory(cache);
        var skeleton = main.Files.First(f => f.Name.EndsWith("Skeleton.hkx", StringComparison.OrdinalIgnoreCase));
        File.WriteAllBytes(Path.Combine(cache, "skeleton.hkx"), skeleton.Bytes);
        int count = 0;
        var compendiums = new Dictionary<string, byte[]>();
        foreach (var (archive, bnd) in found.OrderBy(kv => kv.Key))
        {
            // The game's animations leave their Havok types to the archive's shared compendium; it goes beside them.
            var compendium = bnd.Files.FirstOrDefault(f => f.Name.EndsWith(".compendium", StringComparison.OrdinalIgnoreCase));
            foreach (var f in bnd.Files.Where(f => f.Name.EndsWith(".hkx", StringComparison.OrdinalIgnoreCase) &&
                                                   Path.GetFileName(f.Name).StartsWith("a", StringComparison.OrdinalIgnoreCase)))
            {
                var name = Path.GetFileName(f.Name);
                var group = name.Split('_')[0];
                // A folder takes one archive's compendium; an animation table spread over two archives with different
                // ones gets a folder per archive.
                if (compendium != null && compendiums.TryGetValue(group, out var had) && !had.AsSpan().SequenceEqual(compendium.Bytes))
                    group += "_" + archive.Replace("c0000_", "").Replace(".anibnd", "");
                if (compendium != null) compendiums.TryAdd(group, compendium.Bytes);
                var dir = Path.Combine(cache, "game", group);
                Directory.CreateDirectory(dir);
                File.WriteAllBytes(Path.Combine(dir, name), f.Bytes);
                if (compendium != null) File.WriteAllBytes(Path.Combine(dir, "types.compendium"), compendium.Bytes);
                count++;
            }
        }
        var config = new { exporter = Environment.ProcessPath, repositories = repositories.Select(Path.GetFullPath).ToArray() };
        File.WriteAllText(Path.Combine(cache, "reference.json"),
                          System.Text.Json.JsonSerializer.Serialize(config, new System.Text.Json.JsonSerializerOptions { WriteIndented = true }));
        Console.WriteLine($"skeleton and {count} animations written to {cache}");
        return 0;
    }

    // The archive headers are encrypted with the private half of an RSA key; the public half decrypts them block by block.
    static byte[] DecryptHeader(string bhd, string keyFile)
    {
        var key = (AsymmetricKeyParameter)new PemReader(new StringReader(File.ReadAllText(keyFile))).ReadObject();
        var rsa = new RsaEngine();
        rsa.Init(false, key);
        var input = File.ReadAllBytes(bhd);
        var output = new MemoryStream();
        int block = rsa.GetInputBlockSize();
        for (int i = 0; i < input.Length; i += block)
        {
            var plain = rsa.ProcessBlock(input, i, Math.Min(block, input.Length - i));
            output.Write(new byte[rsa.GetOutputBlockSize() - plain.Length]);  // leading zeros the big integer dropped
            output.Write(plain);
        }
        return output.ToArray();
    }

    static ulong PathHash(string path)
    {
        ulong h = 0;
        foreach (var c in path.ToLowerInvariant()) h = h * 0x85 + c;
        return h;
    }

    // ---- decode -----------------------------------------------------------------------------------------------

    static int Decode(string cache, string hkxPath, string outPath)
    {
        var skeleton = HKX.GenFakeFromTagFile(File.ReadAllBytes(Path.Combine(cache, "skeleton.hkx")), null)
            .DataSection.Objects.OfType<HKX.HKASkeleton>().First();
        var compendium = Path.Combine(Path.GetDirectoryName(Path.GetFullPath(hkxPath)), "types.compendium");
        var objects = HKX.GenFakeFromTagFile(File.ReadAllBytes(hkxPath), File.Exists(compendium) ? File.ReadAllBytes(compendium) : null)
            .DataSection.Objects;
        var frame = objects.OfType<HKX.HKADefaultAnimatedReferenceFrame>().FirstOrDefault();
        var binding = objects.OfType<HKX.HKAAnimationBinding>().First();
        HavokAnimationData anim = objects.OfType<HKX.HKASplineCompressedAnimation>().FirstOrDefault() is { } spline
            ? new HavokAnimationData_SplineCompressed(0, Path.GetFileNameWithoutExtension(hkxPath), skeleton, frame, binding, spline)
            : new HavokAnimationData_InterleavedUncompressed(0, Path.GetFileNameWithoutExtension(hkxPath), skeleton, frame, binding,
                  objects.OfType<HKX.HKAInterleavedUncompressedAnimation>().First());

        var names = skeleton.Bones.GetArrayData().Elements.Select(b => b.Name.GetString()).ToList();
        var parents = skeleton.ParentIndices.GetArrayData().Elements.Select(p => (int)p.data).ToList();
        var rest = skeleton.Transforms.GetArrayData().Elements.Select(t => new NewBlendableTransform
        {
            Translation = new Vector3(t.Position.Vector.X, t.Position.Vector.Y, t.Position.Vector.Z),
            Rotation = new Quaternion(t.Rotation.Vector.X, t.Rotation.Vector.Y, t.Rotation.Vector.Z, t.Rotation.Vector.W),
            Scale = new Vector3(t.Scale.Vector.X, t.Scale.Vector.Y, t.Scale.Vector.Z),
        }).ToList();

        var json = new StringBuilder();
        json.Append("{\"name\":\"").Append(anim.Name).Append("\",\"frame_time\":").Append(F(anim.FrameDuration))
            .Append(",\"frames\":").Append(anim.FrameCount).Append(",\"duration\":").Append(F(anim.Duration))
            .Append(",\"bones\":[").Append(string.Join(",", names.Select(n => "\"" + n + "\""))).Append(']')
            .Append(",\"parents\":[").Append(string.Join(",", parents)).Append(']')
            .Append(",\"rest\":").Append(Pose(rest, parents)).Append(",\"poses\":[");
        for (int f = 0; f < anim.FrameCount; f++)
        {
            var local = new List<NewBlendableTransform>();
            for (int b = 0; b < names.Count; b++)
            {
                int track = anim.HkxBoneIndexToTransformTrackMap != null && b < anim.HkxBoneIndexToTransformTrackMap.Length
                    ? anim.HkxBoneIndexToTransformTrackMap[b] : -1;
                local.Add(track >= 0 ? anim.GetTransformOnFrame(track, f, false) : rest[b]);
            }
            json.Append(f == 0 ? "" : ",").Append(Pose(local, parents));
        }
        json.Append("],\"root\":[");
        var root = anim.RootMotion?.Frames;
        if (root != null)
            json.Append(string.Join(",", root.Select(r => "[" + F(r.X) + "," + F(r.Y) + "," + F(r.Z) + "," + F(r.W) + "]")));
        json.Append("]}");
        File.WriteAllText(outPath, json.ToString());
        return 0;
    }

    // One pose: every bone's model-space position, then its local rotation (x, y, z, w) and translation.
    static string Pose(List<NewBlendableTransform> local, List<int> parents)
    {
        var world = new Matrix4x4[local.Count];
        var position = new List<string>();
        var rotation = new List<string>();
        for (int b = 0; b < local.Count; b++)
        {
            var t = local[b];
            var m = Matrix4x4.CreateScale(t.Scale) * Matrix4x4.CreateFromQuaternion(Quaternion.Normalize(t.Rotation)) *
                    Matrix4x4.CreateTranslation(t.Translation);
            world[b] = parents[b] >= 0 ? m * world[parents[b]] : m;
            position.Add(F(world[b].M41) + "," + F(world[b].M42) + "," + F(world[b].M43));
            var q = Quaternion.Normalize(t.Rotation);
            rotation.Add(F(q.X) + "," + F(q.Y) + "," + F(q.Z) + "," + F(q.W) + "," +
                         F(t.Translation.X) + "," + F(t.Translation.Y) + "," + F(t.Translation.Z));
        }
        return "{\"p\":[" + string.Join(",", position) + "],\"l\":[" + string.Join(",", rotation) + "]}";
    }

    static string F(float v) => float.IsFinite(v) ? Math.Round(v, 4).ToString(System.Globalization.CultureInfo.InvariantCulture) : "0";
}
