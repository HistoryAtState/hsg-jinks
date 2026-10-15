# OPS: enabling vector (hybrid) search on a bare-metal eXist host

## 1. What this changes

- `/search` gains an opt-in `mode=hybrid` that fuses Lucene keyword search (`hsg-fulltext`) with
  KNN over the `hsg-embedding` vector field using reciprocal rank fusion (RRF).
  `mode=keyword` stays the default; any other value falls back to keyword.
- Embeddings are computed **inside eXist** by a local ONNX model, `all-MiniLM-L6-v2`
  (384 dimensions, cosine similarity). No external service, API key or outbound network is needed at runtime.
- Vectors are persisted in `vector.dbx` (`vector-store="db"`) and are created by a **reindex**.
- The application code is already on `main` (PR #74). What production needs is the vector-capable
  eXist runtime, the model files, the `conf.xml` registry entry, JVM flags, and a reindex.

## 2. Prerequisites

| Requirement | Detail |
|---|---|
| JDK | 21 |
| Disk | ~0.7 GiB for `vector.dbx` for the full FRUS corpus (estimate), ~90 MiB for the model, plus space for the pre-change backup and for reindex. |
| RAM | See 4.3. |

## 3. Files on the host

Paths are relative to `$EXIST_HOME`.

| File | Path | Notes |
|---|---|---|
| Model | `onnx-models/all-MiniLM-L6-v2/model.onnx` | 90,445,823 bytes |
| Tokenizer | `onnx-models/all-MiniLM-L6-v2/tokenizer.json` | 711,661 bytes |

### 3.1 Install the model

Download (the same source eXist's own `onnx-model` Maven profile uses):

```shell
M="$EXIST_HOME/onnx-models/all-MiniLM-L6-v2"
mkdir -p "$M"
curl -fL -o "$M/model.onnx" \
  https://huggingface.co/onnx-models/all-MiniLM-L6-v2-onnx/resolve/main/model.onnx
curl -fL -o "$M/tokenizer.json" \
  https://huggingface.co/onnx-models/all-MiniLM-L6-v2-onnx/resolve/main/tokenizer.json
```

Or, for an air-gapped host, extract from the approved image:

```shell
docker create --name hsg-onnx duncdrum/existdb:experimental
docker cp hsg-onnx:/exist/onnx-models ./onnx-models
docker rm hsg-onnx
# then copy ./onnx-models to $EXIST_HOME/onnx-models
```

Verify, and make the files readable by the eXist service user.

Only these two files are needed. The Hugging Face pack also ships `config.json`, `vocab.txt` etc.; they are not used, but do not harm either.

## 4. Configuration

### 4.1 `etc/conf.xml`

In the stock file the block is commented out near the end. Uncomment it, or add it as the last child before `</exist>`.
Keep exactly **one** live `<vector-models>` block.

```xml
<vector-models>
    <model id="all-MiniLM-L6-v2"
           path="onnx-models/all-MiniLM-L6-v2"
           dimension="384"/>
</vector-models>
```

- `path` is resolved relative to `exist.home`; an absolute path also works.
- `id` must equal the `model=` value in every `collection.xconf` and `$srch:EMBED_MODEL` in
  `modules/templates/search.xqm` (`all-MiniLM-L6-v2`).
- `dimension` must equal `dimension="384"` in every `<vector-field>`.

### 4.2 JVM options

Both flags below are **required**. They are what the approved image's entrypoint passes.
Without `jdk.incubator.vector` the Lucene vector code does not load; without `--enable-native-access`
the ONNX/tokenizer native libraries produce warnings or fail on JDK 21+.

```
--enable-native-access=ALL-UNNAMED
--add-modules jdk.incubator.vector
```

### 4.3 Memory

The image uses `-XX:MaxRAMPercentage=75`, which on bare metal means 75% of host RAM. Prefer explicit `-Xms/-Xmx`.
ONNX Runtime allocates **native memory outside the Java heap**, so leave headroom above `-Xmx`.
No heap or RSS measurements exist for this workload: load-test during reindex and hybrid queries and record the numbers here.

### 5 Index definitions from xars (reference, no change needed)

```xml
<lucene vector-store="db">
  <text qname="tei:div">
    <vector-field name="hsg-embedding" expression="."
                  dimension="384" similarity="cosine"
                  embedding="local" model="all-MiniLM-L6-v2"/>
  </text>
</lucene>
```

`vector-store="db"` keeps vectors in `vector.dbx` (included in backups, reused on scoped reindex).
Measured on the dev corpus it was also faster to reindex than `lucene`.
