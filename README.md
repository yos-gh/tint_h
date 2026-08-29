# TINT horizontal

横長のフィールドで、柔らかいテトロミノを細く高く積み上げる物理パズルのプロトタイプです。

[ブラウザでTINT horizontalをプレイ](https://yos-gh.github.io/tint_h/)

## Prototype rules

- 石が緑の消去ラインから底まで縦につながると、その列を消去します。
- 消去に必要な高さは約9石分で、その上に操作用の余白があります。
- 左右の赤いデッドラインを石が5秒間越え続けるとゲームオーバーです。
- 1秒以内に列を続けて消すとコンボ倍率が上がります。同時に複数列を消した場合も列数分だけ倍率が上がります。
- フィールド寸法、デッドライン位置、得点値はプロトタイプ用の仮値です。

## Controls

| Action | Keyboard | Gamepad |
| --- | --- | --- |
| Move | `A` / `D` or arrow keys | D-pad or left stick |
| Soft drop | `S` or down arrow | D-pad down or left stick down |
| Rotate counterclockwise | `N` | `A` or `X` |
| Rotate clockwise | `M` | `B` or `Y` |
| Restart | `R` | — |

Godot 4.7以降で `project.godot` を開くか、次のコマンドで起動できます。

```powershell
Godot.exe --path .
```

Web版は次のコマンドで `web/game` へ出力できます。

```powershell
Godot_console.exe --headless --path . --export-release Web web/game/index.html
```

前作TINTのブロック物理、中央へ寄る凹型の底面、操作、タッチUIを流用しています。
