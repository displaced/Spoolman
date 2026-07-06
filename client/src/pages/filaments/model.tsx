import { IVendor } from "../vendors/model";

export interface ITemperatureSpeedRange {
  temperature: [number | null, number | null];
  print_speed: [number | null, number | null];
}

export interface IFilament {
  id: number;
  registered: string;
  name?: string;
  vendor?: IVendor;
  material?: string;
  price?: number;
  density: number;
  diameter: number;
  weight?: number;
  spool_weight?: number;
  article_number?: string;
  comment?: string;
  settings_bed_temp?: number;
  temperature_speed_ranges?: ITemperatureSpeedRange[];
  color_hex?: string;
  multi_color_hexes?: string;
  multi_color_direction?: string;
  external_id?: string;
  extra: { [key: string]: string };
}

// IFilamentParsedExtras is the same as IFilament, but with the extra field parsed into its real types
export type IFilamentParsedExtras = Omit<IFilament, "extra"> & { extra?: { [key: string]: unknown } };
