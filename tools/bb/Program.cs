// One Bloodborne character model, read from the player's own dump for the monster replacement tools (tools/bb).
//
//   BbModel list <chr folder>
//       Every character archive in the folder (c????.chrbnd.dcx): its meshes, vertices, triangles, bones and
//       textures, one line each, to choose a model from.
//   BbModel export <character archive> <out folder> [more archives...]
//       Writes <out>/model.json (the skeleton, the materials, and every mesh's vertices, bone weights and triangles)
//       and <out>/textures/<name>.dds (every texture in the archives, with a DDS header). More archives are read for
//       textures only (a character's textures can sit in an archive of their own).
//
// Everything it writes goes to the out folder, which must be outside the repository: these are FromSoftware's files
// and stay on the player's machine. model.json's layout is in README.md.

using System.Collections;
using System.Numerics;
using System.Text.Json;
using SoulsFormats;

static class BbModel
{
    static int Main(string[] args)
    {
        try
        {
            if (args.Length == 2 && args[0] == "list") return List(args[1]);
            if (args.Length >= 3 && args[0] == "export") return Export(args[1], args[2], args[3..]);
        }
        catch (Exception e)
        {
            Console.Error.WriteLine(e.Message);
            return 1;
        }
        Console.Error.WriteLine("usage: BbModel list <chr folder>\n" +
                                "       BbModel export <character archive> <out folder> [more archives...]");
        return 2;
    }

    // ---- reading ------------------------------------------------------------------------------------------------

    static BND4 OpenArchive(string path)
    {
        var bytes = File.ReadAllBytes(path);
        return BND4.Read(DCX.Is(bytes) ? DCX.Decompress(bytes) : bytes);
    }

    static byte[] Plain(byte[] bytes) => DCX.Is(bytes) ? DCX.Decompress(bytes) : bytes;

    /// The archive's model: the first member that is a FLVER2 (a character archive has one).
    static FLVER2 ModelOf(BND4 archive, out string name)
    {
        foreach (var f in archive.Files)
        {
            if (!f.Name.EndsWith(".flver", StringComparison.OrdinalIgnoreCase) &&
                !f.Name.EndsWith(".flver.dcx", StringComparison.OrdinalIgnoreCase)) continue;
            var bytes = Plain(f.Bytes);
            if (!FLVER2.Is(bytes)) continue;
            name = Path.GetFileName(f.Name.Replace('\\', '/'));
            return FLVER2.Read(bytes);
        }
        name = null;
        return null;
    }

    static IEnumerable<TPF.Texture> TexturesOf(BND4 archive)
    {
        foreach (var f in archive.Files)
        {
            if (!f.Name.EndsWith(".tpf", StringComparison.OrdinalIgnoreCase) &&
                !f.Name.EndsWith(".tpf.dcx", StringComparison.OrdinalIgnoreCase)) continue;
            var bytes = Plain(f.Bytes);
            if (!TPF.Is(bytes)) continue;
            foreach (var t in TPF.Read(bytes).Textures) yield return t;
        }
    }

    // The library's names for a few members changed between its versions (a model's Nodes were Bones, a mesh's
    // NodeIndex was DefaultBoneIndex, a material texture's ParamName was Type). Read whichever this build has.
    static object Member(object o, params string[] names)
    {
        var type = o.GetType();
        foreach (var n in names)
        {
            if (type.GetProperty(n) is { } p) return p.GetValue(o);
            if (type.GetField(n) is { } f) return f.GetValue(o);
        }
        throw new MissingMemberException(type.FullName, string.Join(" or ", names));
    }

    static List<object> NodesOf(FLVER2 model) => ((IEnumerable)Member(model, "Nodes", "Bones")).Cast<object>().ToList();

    /// A face set of the full-detail model: not a lower level of detail, not the motion blur copy.
    static bool FullDetail(FLVER2.FaceSet set) => ((uint)set.Flags & 0x8700_0000u) == 0;

    static List<int> TrianglesOf(FLVER2.Mesh mesh)
    {
        if (mesh.FaceSets.Count == 0) return new List<int>();
        var set = mesh.FaceSets.Find(FullDetail) ?? mesh.FaceSets[0];
        var indices = set.Triangulate(mesh.Vertices.Count < ushort.MaxValue);
        // A triangle that names a vertex the mesh does not have is left out, whole.
        var triangles = new List<int>(indices.Count);
        for (int i = 0; i + 2 < indices.Count; i += 3)
        {
            int a = indices[i], b = indices[i + 1], c = indices[i + 2];
            if (a < 0 || b < 0 || c < 0 || a >= mesh.Vertices.Count || b >= mesh.Vertices.Count || c >= mesh.Vertices.Count) continue;
            triangles.Add(a); triangles.Add(b); triangles.Add(c);
        }
        return triangles;
    }

    // ---- list ---------------------------------------------------------------------------------------------------

    static int List(string folder)
    {
        var paths = Directory.GetFiles(folder, "*.chrbnd.dcx").Concat(Directory.GetFiles(folder, "*.chrbnd")).OrderBy(p => p).ToList();
        if (paths.Count == 0) throw new FileNotFoundException("no character archives (*.chrbnd.dcx) in " + folder);
        Console.WriteLine("archive            meshes  vertices  triangles  bones  textures");
        foreach (var path in paths)
        {
            var id = Path.GetFileName(path);
            id = id.Substring(0, id.IndexOf('.'));
            try
            {
                var archive = OpenArchive(path);
                var model = ModelOf(archive, out _);
                if (model == null) { Console.WriteLine($"{id,-18} no model"); continue; }
                int vertices = model.Meshes.Sum(m => m.Vertices.Count);
                int triangles = model.Meshes.Sum(m => TrianglesOf(m).Count / 3);
                Console.WriteLine($"{id,-18} {model.Meshes.Count,6}  {vertices,8}  {triangles,9}  {NodesOf(model).Count,5}  {TexturesOf(archive).Count(),8}");
            }
            catch (Exception e)
            {
                Console.WriteLine($"{id,-18} not read: {e.Message}");
            }
        }
        return 0;
    }

    // ---- export -------------------------------------------------------------------------------------------------

    static int Export(string archivePath, string outFolder, string[] moreArchives)
    {
        var archive = OpenArchive(archivePath);
        var model = ModelOf(archive, out var modelName) ?? throw new InvalidDataException("no FLVER2 model in " + archivePath);
        Directory.CreateDirectory(Path.Combine(outFolder, "textures"));

        // Textures first: the model's materials name them, and model.json says which were written.
        var written = new List<(string name, byte format, int width, int height)>();
        var failed = new List<(string name, string error)>();
        var seen = new HashSet<string>(StringComparer.OrdinalIgnoreCase);
        foreach (var source in new[] { archive }.Concat(moreArchives.Select(OpenArchive)))
        {
            foreach (var t in TexturesOf(source))
            {
                if (!seen.Add(t.Name)) continue;
                try
                {
                    File.WriteAllBytes(Path.Combine(outFolder, "textures", t.Name + ".dds"), t.Headerize());
                    written.Add((t.Name, t.Format, t.Header?.Width ?? 0, t.Header?.Height ?? 0));
                }
                catch (Exception e)
                {
                    failed.Add((t.Name, e.Message));
                }
            }
        }

        var nodes = NodesOf(model);
        var world = new Matrix4x4[nodes.Count];
        using (var stream = File.Create(Path.Combine(outFolder, "model.json")))
        using (var json = new Utf8JsonWriter(stream, new JsonWriterOptions { Indented = false }))
        {
            json.WriteStartObject();
            json.WriteString("format", "moonmod-bb-model");
            json.WriteNumber("version", 1);
            json.WriteString("source", modelName);
            json.WriteNumber("flver_version", model.Header.Version);

            json.WriteStartArray("nodes");
            for (int i = 0; i < nodes.Count; i++)
            {
                var n = nodes[i];
                var t = (Vector3)Member(n, "Translation");
                var r = (Vector3)Member(n, "Rotation");
                var s = (Vector3)Member(n, "Scale");
                int parent = Convert.ToInt32(Member(n, "ParentIndex"));
                // The file's own bone transform: scale, then turns about X, Z and Y, then the move (row vectors).
                var local = Matrix4x4.CreateScale(s) * Matrix4x4.CreateRotationX(r.X) * Matrix4x4.CreateRotationZ(r.Z) *
                            Matrix4x4.CreateRotationY(r.Y) * Matrix4x4.CreateTranslation(t);
                // A parent always comes before its children in these files; one that does not is treated as a root.
                world[i] = parent >= 0 && parent < i ? local * world[parent] : local;
                json.WriteStartObject();
                json.WriteString("name", (string)Member(n, "Name"));
                json.WriteNumber("parent", parent);
                Floats(json, "translation", t.X, t.Y, t.Z);
                Floats(json, "rotation", r.X, r.Y, r.Z);
                Floats(json, "scale", s.X, s.Y, s.Z);
                var w = world[i];
                Floats(json, "world", w.M11, w.M12, w.M13, w.M14, w.M21, w.M22, w.M23, w.M24,
                                      w.M31, w.M32, w.M33, w.M34, w.M41, w.M42, w.M43, w.M44);
                json.WriteEndObject();
            }
            json.WriteEndArray();

            json.WriteStartArray("materials");
            foreach (var m in model.Materials)
            {
                json.WriteStartObject();
                json.WriteString("name", m.Name);
                json.WriteString("mtd", m.MTD);
                json.WriteStartArray("textures");
                foreach (var t in m.Textures)
                {
                    json.WriteStartObject();
                    json.WriteString("param", (string)Member(t, "ParamName", "Type"));
                    json.WriteString("path", t.Path);
                    // The texture's name in the archive: the path's file name without its extension.
                    json.WriteString("file", string.IsNullOrEmpty(t.Path) ? "" : Path.GetFileNameWithoutExtension(t.Path.Replace('\\', '/')));
                    json.WriteEndObject();
                }
                json.WriteEndArray();
                json.WriteEndObject();
            }
            json.WriteEndArray();

            // Vertices whose bone numbers count within the mesh's own bone list (older files) or within the whole
            // skeleton (Bloodborne's), as DSAnimStudio reads them.
            bool perMeshBones = model.Header.Version <= 0x2000D;
            json.WriteStartArray("meshes");
            foreach (var mesh in model.Meshes)
            {
                bool hasBoneIndices = mesh.VertexBuffers.Any(b =>
                    model.BufferLayouts[b.LayoutIndex].Any(member => member.Semantic == FLVER.LayoutSemantic.BoneIndices));
                bool skinned = Convert.ToInt32(Member(mesh, "UseBoneWeights", "Dynamic")) != 0;
                var triangles = TrianglesOf(mesh);
                json.WriteStartObject();
                json.WriteNumber("material", mesh.MaterialIndex);
                json.WriteNumber("node", Convert.ToInt32(Member(mesh, "NodeIndex", "DefaultBoneIndex")));
                json.WriteBoolean("dynamic", skinned);
                json.WriteBoolean("has_bone_indices", hasBoneIndices);
                json.WriteNumber("vertex_count", mesh.Vertices.Count);
                json.WriteNumber("triangle_count", triangles.Count / 3);

                json.WriteStartArray("positions");
                foreach (var v in mesh.Vertices) { json.WriteNumberValue(v.Position.X); json.WriteNumberValue(v.Position.Y); json.WriteNumberValue(v.Position.Z); }
                json.WriteEndArray();
                json.WriteStartArray("normals");
                foreach (var v in mesh.Vertices) { json.WriteNumberValue(v.Normal.X); json.WriteNumberValue(v.Normal.Y); json.WriteNumberValue(v.Normal.Z); }
                json.WriteEndArray();
                json.WriteStartArray("uvs");
                foreach (var v in mesh.Vertices)
                {
                    json.WriteNumberValue(v.UVs.Count > 0 ? v.UVs[0].X : 0f);
                    json.WriteNumberValue(v.UVs.Count > 0 ? v.UVs[0].Y : 0f);
                }
                json.WriteEndArray();

                var joints = new int[mesh.Vertices.Count * 4];
                var weights = new float[mesh.Vertices.Count * 4];
                for (int i = 0; i < mesh.Vertices.Count; i++)
                {
                    var v = mesh.Vertices[i];
                    var index = new[] { v.BoneIndices[0], v.BoneIndices[1], v.BoneIndices[2], v.BoneIndices[3] };
                    var weight = new[] { v.BoneWeights[0], v.BoneWeights[1], v.BoneWeights[2], v.BoneWeights[3] };
                    if (weight[0] == 0 && weight[1] == 0 && weight[2] == 0 && weight[3] == 0) weight[0] = 1;
                    if (!hasBoneIndices)
                    {
                        // A mesh with no bone numbers of its own hangs each vertex on one bone, kept in the normal.
                        index = new[] { v.NormalW, 0, 0, 0 };
                        weight = new[] { 1f, 0f, 0f, 0f };
                    }
                    for (int k = 0; k < 4; k++)
                    {
                        int bone = index[k];
                        if (perMeshBones) bone = bone >= 0 && bone < mesh.BoneIndices.Count ? mesh.BoneIndices[bone] : -1;
                        if (bone < 0 || bone >= nodes.Count) { bone = 0; weight[k] = 0; }
                        joints[i * 4 + k] = bone;
                        weights[i * 4 + k] = weight[k];
                    }
                }
                json.WriteStartArray("joints");
                foreach (var j in joints) json.WriteNumberValue(j);
                json.WriteEndArray();
                json.WriteStartArray("weights");
                foreach (var w in weights) json.WriteNumberValue(w);
                json.WriteEndArray();
                json.WriteStartArray("triangles");
                foreach (var t in triangles) json.WriteNumberValue(t);
                json.WriteEndArray();
                json.WriteEndObject();
            }
            json.WriteEndArray();

            json.WriteStartArray("textures");
            foreach (var t in written)
            {
                json.WriteStartObject();
                json.WriteString("name", t.name);
                json.WriteString("file", "textures/" + t.name + ".dds");
                json.WriteNumber("format", t.format);
                json.WriteNumber("width", t.width);
                json.WriteNumber("height", t.height);
                json.WriteEndObject();
            }
            json.WriteEndArray();
            json.WriteStartArray("texture_errors");
            foreach (var t in failed)
            {
                json.WriteStartObject();
                json.WriteString("name", t.name);
                json.WriteString("error", t.error);
                json.WriteEndObject();
            }
            json.WriteEndArray();
            json.WriteEndObject();
        }

        Console.WriteLine($"{modelName}: {model.Meshes.Count} meshes, {model.Meshes.Sum(m => m.Vertices.Count)} vertices, " +
                          $"{model.Meshes.Sum(m => TrianglesOf(m).Count / 3)} triangles, {nodes.Count} bones, " +
                          $"{written.Count} textures written, {failed.Count} not");
        foreach (var t in failed) Console.Error.WriteLine($"texture {t.name}: {t.error}");
        return 0;
    }

    static void Floats(Utf8JsonWriter json, string name, params float[] values)
    {
        json.WriteStartArray(name);
        foreach (var v in values) json.WriteNumberValue(v);
        json.WriteEndArray();
    }
}
