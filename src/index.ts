import { UnavailabilityError } from "expo-modules-core";

import BgRemoverModule from "./BgRemoverModule";

export async function getSubjectAsync(
  url: string,
  pointX: number = 0.5,
  pointY: number = 0.5,
  cropToExtent: boolean = false,
): Promise<any> {
  if (!BgRemoverModule.getSubjectAsync) {
    throw new UnavailabilityError("BgRemover", "getSubjectAsync");
  }

  return await BgRemoverModule.getSubjectAsync(
    url,
    pointX,
    pointY,
    cropToExtent,
  );
}
