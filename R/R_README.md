# R Functions

This folder contains reusable R functions for data preparation, exploration, visualization, and modeling.

- `repair_csv_encoding.R`: repairs CSV files containing stray single-byte characters (e.g. a Windows-1252 byte that isn't valid UTF-8 on its own) by rewriting them to proper UTF-8 and writing a repaired copy, leaving the original file untouched.