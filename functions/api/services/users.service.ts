import { sbAdmin } from "./supabase.ts";

export type OrgUserDto = {
  user_id: string;
  role: "athlete" | "coach";
  full_name : string | null;
  phone: string | null;
  graduation_year: number | null;
};

function mapPhone(row: any): string | null {
  return row?.cell_number ?? row?.phone ?? null;
}

export async function listOrgUsers(
  org_id: string,
): Promise<{ data: OrgUserDto[]; count: number; error: unknown }> {
  const client = sbAdmin;
  if (!client) {
    return { data: [], count: 0, error: new Error("Supabase client not initialized") };
  }

  const [athletesResult, coachesResult] = await Promise.all([
    client
      .from("athletes")
      .select("user_id, full_name, cell_number, graduation_year")
      .eq("org_id", org_id),
    client
      .from("coaches")
      .select("user_id, full_name, cell_number")
      .eq("org_id", org_id),
  ]);

  if (athletesResult.error) {
    return { data: [], count: 0, error: athletesResult.error };
  }
  if (coachesResult.error) {
    return { data: [], count: 0, error: coachesResult.error };
  }

  const athletes: OrgUserDto[] = (athletesResult.data ?? [])
    .filter((row: any) => row?.user_id)
    .map((row: any) => ({
      user_id: row.user_id,
      role: "athlete",
      full_name: row.full_name ?? null,
      phone: mapPhone(row),
      graduation_year: row.graduation_year ?? null,
    }));

  const coaches: OrgUserDto[] = (coachesResult.data ?? [])
    .filter((row: any) => row?.user_id)
    .map((row: any) => ({
      user_id: row.user_id,
      role: "coach",
      full_name: row.full_name ?? null,
      phone: mapPhone(row),
      graduation_year: null,
    }));

  const items = [...athletes, ...coaches].sort((a, b) => {
    const last = (a.full_name ?? "").localeCompare(b.full_name ?? "");
    if (last !== 0) return last;
    return (a.user_id ?? "").localeCompare(b.user_id ?? "");
  });

  return { data: items, count: items.length, error: null };
}
