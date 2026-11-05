/// Explicit, deterministic offline tools. No eval or remote side effects.
class LocalTools {
  static String timeText(DateTime now) {
    final local=now.toLocal();
    const weekdays=['星期一','星期二','星期三','星期四','星期五','星期六','星期日'];
    String pad(int v)=>v.toString().padLeft(2,'0');
    return '手机本地时间：${local.year}年${local.month}月${local.day}日 '
      '${weekdays[local.weekday-1]} ${pad(local.hour)}:${pad(local.minute)}:${pad(local.second)} '
      '(${local.timeZoneName})。如手机系统时间不正确，请先校时。';
  }

  static String? calculate(String expression) {
    final input=expression.replaceAll(' ','').trim();
    if(input.length>90) return '表达式太长，请分步计算。';
    final re=RegExp(r'^(-?\d+(?:\.\d+)?)([+*/-])(-?\d+(?:\.\d+)?)$');
    final match=re.firstMatch(input);
    if(match==null) return '目前支持简单四则运算，例如 /calc 24*3 或 /calc 7/2。';
    final a=double.tryParse(match.group(1)!);
    final b=double.tryParse(match.group(3)!);
    if(a==null || b==null) return '数字无法解析。';
    final sign=match.group(2)!;
    if(sign=='/' && b==0) return '不能除以零。';
    final value=switch(sign){
      '+'=>a+b,'-'=>a-b,'*'=>a*b,'/'=>a/b,_=>double.nan,
    };
    if(!value.isFinite) return '计算结果超出有效范围。';
    final result=value==value.roundToDouble() ? value.round().toString() : value.toStringAsPrecision(12);
    return '$input = $result（本地计算工具）';
  }

  static String? run(String raw, DateTime now) {
    final text=raw.trim();
    if(text=='/time' || text=='/时间') return timeText(now);
    if(text.startsWith('/calc ') || text.startsWith('/计算 ')) {
      return calculate(text.substring(text.indexOf(' ')+1)) ?? '无法计算。';
    }
    return null;
  }
}
