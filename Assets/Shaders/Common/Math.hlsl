bool coneIntersection(float3 ray_ori, float3 ray_dir, float R, float H, out float t_near, out float t_far)
{
    // ============
    // 求解射线 O + t · D 与 圆锥 x² + z² = (R/H)² · y² 的交点
    // ============
    // 联立后是一个二元一次方程
    float k2 = pow((R / H), 2);

    float a = ray_dir.x * ray_dir.x + ray_dir.z * ray_dir.z - k2 * ray_dir.y * ray_dir.y;
    float b = 2.0f * (ray_ori.x * ray_dir.x + ray_ori.z * ray_dir.z - k2 * ray_ori.y * ray_dir.y);
    float c = ray_ori.x * ray_ori.x + ray_ori.z * ray_ori.z - k2 * ray_ori.y * ray_ori.y;

    float delta = b * b - 4.0f * a * c;
    if (delta < 0.000f) return false; // 没打中
    float sqrt_delta = sqrt(delta);

    half has_enter = step(c, 0.0f) * step(0.0f, ray_ori.y); // f(0) = c,  c <0 说明视线起点在内部，加上起点在上半圆锥 ，t_near 直接为 0
    t_near = 0.0f;

    // O +tD 代入圆锥方程以后得到一元二次方程 f(t) = at² + bt + c，导数是2at + b
    // 把 t_1 和 t_2 代入导数， dt_1 = -sart_delta < 0, dt_2 = sqrt_delta > 0
    // 在圆锥表面，f(t) = 0， 圆锥内部 (t) < 0，圆锥外部 f(t) > 0
    // 入口 f(t) 从 >0 -> <0, 导数是负数，t_1天生是入射点
    // 出口 f(t) 从 <0 -> >0, 导数是正数，t_2天生是出射点
    float t_1 = (-b - sqrt_delta) / (2.0f * a);
    float t_2 = (-b + sqrt_delta) / (2.0f * a);

    // ==================== 处理 t_1 (它命中注定是 Enter) ====================
    float y1 = ray_ori.y + t_1 * ray_dir.y;
    half valid1 = step(0.0f, t_1) * step(0.0f, y1); // t_1 >= 0 且 y1 >= 0 , 判断 t_1 在射线前方且在上半空间

    // 如果 t_1 有效，它必定是入口, 入口计算完成！
    has_enter = max(has_enter, valid1);
    t_near = lerp(t_near, t_1, valid1);

    // ==================== 处理 t_2 (它命中注定是 Exit) ====================
    float y2 = ray_ori.y + t_2 * ray_dir.y;
    half valid2 = step(0.0f, t_2) * step(0.0f, y2);

    // 如果 t_2 有效，它必定是出口，出口计算完成！
    t_far = lerp(100000.0f, t_2, valid2); // 如果没出口，默认为深空(100000.0)

    // ==================== 结算 ====================
    if (has_enter < 0.5h) return false; // 没有入口，完全没击中
    return true;
}

half erfApproximate(half x)
{
    half x2 = x * x;
    // 1.27323954  是 4 / PI 的近似值
    half val = sqrt(1.0h - exp(-1.27323954h * x2));
    return sign(x) * val;
}

bool AABB(float3 ray_ori, float3 ray_dir, float L, out float t_near, out float t_far)
{
    float3 box_min = float3(-L, -L, -L);
    float3 box_max = float3(L, L, L);

    float3 inv_ray_dir_os = 1.0f / (ray_dir + 1e-5);

    float3 t1 = (box_min - ray_ori) * inv_ray_dir_os;
    float3 t2 = (box_max - ray_ori) * inv_ray_dir_os;

    float3 t_in = min(t1, t2);
    float3 t_out = max(t1, t2);

    t_near = max(t_in.z, max(t_in.x, t_in.y));
    t_far = min(t_out.z, min(t_out.x, t_out.y));

    if (t_near > t_far) return false;
    t_near = max(0.0, t_near);
    return true;
}
