##################################################################
#              Descarga y alineamiento de secuencias             #
##################################################################
#if (!requireNamespace("BiocManager", quietly=TRUE))
#  install.packages("BiocManager")
#BiocManager::install("msa")

library(ape)
library(msa)

# set wd en la carpeta inputs_outputs
setwd("C:/Users/vicen/Documents/cursos_y_seminarios/filogeografia_2026_1/inputs_outputs")
data_basins <- read.csv("basins_metadata.csv")
data_basins <- data_basins[order(data_basins$COI), ]
head(data_basins)

# Secuencias genbank
secs_coi <- c(data_basins$COI)
secs_coi

# Download secs
secs_coi_gb <- read.GenBank(secs_coi, species.names = TRUE,
             as.character = FALSE)

# Cambiar los nombres con el vector de nombres 
secs_coi_names <- paste(data_basins$COI, data_basins$Lineage, data_basins$Basin, data_basins$Fresh_water, sep = "_")
names(secs_coi_gb) <- secs_coi_names
# Save in fasta format
write.dna(secs_coi_gb, "secs_coi_gb.fasta", colsep = "", colw = 900, format = "fasta")

# Para realizar el alineamiento
sequences_coi <- readAAStringSet("secs_coi_gb.fasta")
sequences_coi
muscle_alignment <- msa(sequences_coi, "Muscle")
muscle_alignment

# Función para guardar el alineamiento en Fasta
alignment2Fasta <- function(alignment, filename) {
  sink(filename)
  
  n <- length(rownames(alignment))
  for(i in seq(1, n)) {
    cat(paste0('>', rownames(alignment)[i]))
    cat('\n')
    the.sequence <- toString(unmasked(alignment)[[i]])
    cat(the.sequence)
    cat('\n')  
  }
  sink(NULL)
}

# Convert to fasta format
alignment2Fasta(muscle_alignment, 'muscle_alignment.fasta')

# Read alignment
coi.align <- read.dna("muscle_alignment.fasta", format="fasta", as.matrix=TRUE)
# Cortar a seqs de la misma longitud
coi.align.trimmed <- coi.align[,64:638]
# Sort by labels (sequence names)
coi.align.trimmed_sorted <- coi.align.trimmed[order(rownames(coi.align.trimmed)), ]
coi.align.trimmed_sorted
write.dna(coi.align.trimmed_sorted, "coi.align.trimmed.fasta", colsep = "", colw = 900, format = "fasta")

##################################################################
#                     Red de Haplotipos                         #
##################################################################
BiocManager::install("GenomicRanges")
BiocManager::install("rtracklayer", force = TRUE)
BiocManager::install("geneHapR")
install.packages("geneHapR")
library(geneHapR)

# Import seqs
align_coi_seqs <- import_seqs("coi.align.trimmed.fasta", format = "fasta")
 
# Calculate haplotype result from aligned DNA sequences.
names(align_coi_seqs)
coi_hapResult <- seqs2hap(align_coi_seqs,
                      Ref = names(seqs)[1]   ,
                      hapPrefix = "H",
                      hetero_remove = FALSE,
                      na_drop = FALSE,
                      maxGapsPerSeq = 0.5)

# Chech number of sites conclude in hapResult
sites(coi_hapResult)

# create df con all info
hapres_df <- as.data.frame(coi_hapResult)
hapres_df_secs <- hapres_df[5:nrow(hapres_df), ]
head(hapres_df_secs)

# previous df
head(data_basins)
data_basins_df <- as.data.frame(data_basins)
head(data_basins_df)

# merge base de datos con base de haplotipos
df_all_info <- cbind(data_basins_df, hapres_df_secs)
head(df_all_info)

################################
# Create nexus files for popart
library(dplyr)

# select each haplotype
df_one_per_name <- df_all_info %>%
  distinct(Hap, .keep_all = TRUE)

ncols_dna <- ncol(df_one_per_name)-1
df_nexus <- df_one_per_name[ ,12:ncols_dna]

# Convierte el data frame a una lista de secuencias
# y almacenar estas secuencias en una lista, asignándoles nombres según la primera columna
seq_list <- setNames(
  lapply(1:nrow(df_nexus), function(i) {
    # Tomar la fila i sin la primera columna y convertirla a vector de caracteres
    as.character(unlist(df_nexus[i, -1]))
  }),
  df_nexus[, 1]  # Usar la primera columna como nombres de las secuencias
)

# Guardar la lista de secuencias en un archivo NEXUS
write.nexus.data(
  seq_list,                # La lista con secuencias convertidas
  file = "1_haplotypes.nex", # Nombre del archivo de salida
  format = "dna",          # Indicar que las secuencias son de ADN
  interleaved = FALSE
)

################
# Create matrix with groups and haplotypes per group
head(df_all_info)

# Create the Hap × Lineage matrix
hap_lineage_matrix <- table(df_all_info$Hap, df_all_info$Basin)
# Convert to a data frame and then matrix, with row names
char_matrix <- as.matrix(hap_lineage_matrix)

# Write NEXUS file
# Open a connection to a .txt file
file_conn <- file("2_hap_lineage_matrix.nex", "w")

# Write NEXUS header
writeLines("#NEXUS", file_conn)
writeLines("", file_conn)
writeLines("BEGIN TRAITS;", file_conn)

# Dimensions
ntraits <- ncol(hap_lineage_matrix)
writeLines(paste0("  DIMENSIONS NTRAITS=", ntraits, ";"), file_conn)
# Format line
writeLines("  FORMAT labels=yes MISSING=? separator=Comma;", file_conn)
# Escribir una línea que empiece con "Traitlabels " seguido de los valores
writeLines(paste("Traitlabels", paste(labels_matrix[[2]], collapse = " "), ";"), file_conn)
# Matrix block
writeLines("  MATRIX", file_conn)

# Write the matrix rows with tab separation
for (i in 1:nrow(hap_lineage_matrix)) { # Hap × Lineage matrix
  row_name <- rownames(hap_lineage_matrix)[i] #extraer el nombre del haplotipo
  row_values <- paste(hap_lineage_matrix[i, ], collapse = ",") # extraer el número de haplotipos presente
  writeLines(paste0("  ", row_name, " ", row_values), file_conn)
}

# Close matrix block
writeLines("  ;", file_conn)
writeLines("END;", file_conn)

# Close the file connection
close(file_conn)

###############################
#Geo tags
#Remover filas con NA en Latitude o Longitude
df_clean <- df_all_info %>%
  filter(!is.na(Latitude) & !is.na(Longitude))

# Agrupar por Hap, Latitude y Longitude y contar ocurrencias
matriz_hap <- df_clean %>%
  group_by(Hap, Latitude, Longitude) %>%
  summarise(count = n(), .groups = "drop") 
# n() es una función de dplyr que cuenta el número de filas en cada grupo.

# Mostrar resultado
print(matriz_hap)

######################################
#Hacer el nexus
# Define el nombre del archivo
nexus_file <- "2b_geotags.nex"

# Abre conexión para escribir
con <- file(nexus_file, "w")

# Comienza el bloque GEOTAGS
writeLines("Begin GeoTags;", con)
nclust=50
writeLines(paste0("Dimensions NClust=",nclust, ";"), con)
writeLines("Format labels=yes separator=Spaces;", con)
writeLines("Matrix", con)

# Escribe cada fila con formato
apply(matriz_hap, 1, function(row) {
  line <- paste(row["Hap"], row["Latitude"], 
                             row["Longitude"], row["count"], sep=" ")
  writeLines(line, con)
})

# Termina el bloque
writeLines(";", con)
writeLines("END;", con)

# Cierra conexión
close(con)

# Hacer los análisis en PopArt
# Concatena el archivo 1 con el archivo 2 o 2b.

######################################
#                 PCA                #
######################################
# Extract population info from sequence names
pop_names <- sapply(strsplit(rownames(seqs_aligned), "_"), `[`, 2)

# Convert to genind
gen <- DNAbin2genind(seqs_aligned, pop = as.factor(pop_names))

# Perform PCA
x <- scaleGen(gen, NA.method = "mean")  # handles missing data
pca_result <- dudi.pca(x, cent = TRUE, scale = FALSE, scannf = FALSE, nf = 3)

# Plot PCA
s.class(pca_result$li, pop(gen), col = rainbow(length(unique(pop(gen)))))

##############################################
#                   Geneland                 #
##############################################
# devtools::install_github('gilles-guillot/Geneland')
library(Geneland)

# load csv
head(data_basins)
# Coords
with_coords <- na.omit(data_basins)

# sequences
seqs_aligned
# Check sequence names
rownames(seqs_aligned)
# Extract sequence names
ind_names <- with_coords$COI

# Create a logical vector: TRUE if row name starts with one of the names_vector
matches_names <- sapply(rownames(seqs_aligned), function(x) any(startsWith(x, ind_names)))
matches_names

# Subset the DNAbin object
selected_dna <- seqs_aligned[matches_names, ]

# Convert DNAbin to genind
genind_obj <- DNAbin2genind(selected_dna)

# Extract sequence names
names <- rownames(selected_dna)
id <- strsplit(names, "_")
basin_samples <- sapply(id, `[`, 1) #seleccionar el primer string 
pop(genind_obj) <- as.factor(basin_samples)

#  convert the data for Geneland:
geneland_input <- genind2genpop(genind_obj)

# Coordinates
coords <- with_coords[ ,c(6,8)]
nrow(coords)

# Extract the genotype matrix
# Each row = individual, each column = locus (SNP or variable position)
genotypes <- geneland_input@tab  # This is the geno.haploid.data
genotypes_matrix <-as.matrix(genotypes)

#Create output directory
dir.create("geneland_haploid_output", showWarnings = FALSE)

# STEP 5: Run the Geneland MCMC algorithm for haploid data
Geneland::MCMC(
  coordinates = coords,                  # Geographic coordinates (lon, lat)
  geno.hap = genotypes_matrix,       # Genotype matrix (coded as integers)
  npopmin = 1,                          # Usually same as Kmin
  npopmax = 8,                          # Usually same as Kmax
  filter.null.alleles = FALSE,
  spatial = TRUE,                       # Use spatial information (TRUE/FALSE)
  freq.model = "Uncorrelated",           # Allele frequency model (Dirichlet = default)
  nit = 50000,                          # Total number of MCMC iterations
  thinning = 100,                       # Save every 100th iteration
  path.mcmc = "geneland_haploid_output/" # Folder to save output
)

# Post-process and visualize the results
PostProcessChain(coords, path.mcmc = "geneland_haploid_output/", burnin = 100, nxdom = 100, nydom = 100)
??PostProcessChain

# Plots
Geneland::Plotnpop(path.mcmc = "geneland_haploid_output/", burnin = 100)
Geneland::PlotTessellation(coords,path.mcmc = "geneland_haploid_output/")
Geneland::PosteriorMode(coords,path.mcmc = "geneland_haploid_output/")

##################################################################
#             Estadísticos Poblacionales                         #
##################################################################

#########
# AMOVA #
#########

library(adegenet)
library(ape)
library(pegas)
library(poppr)
library(hierfstat)

# Leer el alineamiento
seqs_aligned <- read.dna("coi.align.trimmed.fasta", format = "fasta")

# sequence names
seq_names <- rownames(seqs_aligned)
pop_names <-strsplit(seq_names, "_")  # get the second element (pop)

# Jerarquizar las muestras (strata)
strata_df <- data.frame(
  individual = seq_names,
  region = sapply(pop_names, `[`, 2),
  basin = sapply(pop_names, `[`, 3),
  river = sapply(pop_names, `[`, 4),
  stringsAsFactors = TRUE
)

# Step 3: Add strata to the genind object
strata(gen) <- strata_df[, -1]  # exclude individual name

#  Define which stratum to use as population
setPop(gen) <- ~region # or ~basin

# do hierarchical AMOVA:
amova_res_basin <- poppr.amova(gen, ~region/basin)
amova_res_basin

# do hierarchical AMOVA:
amova_res_reg <- poppr.amova(gen, ~region)
amova_res_reg

##Recuerden ser muy explícitos con sus métodos

##########
#  FST   #
#########

# Convert to hierfstat
gen_hierf <- genind2hierfstat(gen)

# Calculate pairwise Fst
pw_fst <- pairwise.WCfst(gen_hierf)   # ver argumentos de la función!!!!

# View the result
round(pw_fst, 4)

####################
# D'Tajima, pi y H #
####################

# Create results table
#Indicar el nombre de la columna y el tipo de dato que recibe
results <- data.frame(
  Population = character(),
  N = integer(),
  Haplotype_diversity = numeric(),
  Nucleotide_diversity = numeric(),
  Tajimas_D = numeric(),
  stringsAsFactors = FALSE
)

# Loop over unique populations
for (p in unique(pop_names)) {
  pop_seq <- seqs[pop_names == p, ] #Agrupar seqs de cada pop
  pop_seqs <- as.DNAbin(pop_seq) #Dar formato 
assign(paste0(p, "_population"), pop_seqs) #Guardar objetos del loop
  
#Calcular los estadísticos
      h_div <- hap.div(pop_seqs)
    pi <- nuc.div(pop_seqs)
    d <- tajima.test(pop_seqs)$D

    # Dar formato a la tabla de resultados
    results <- rbind(results, data.frame(
      Population = p,
      N = length(pop_seq),
      Haplotype_diversity = round(h_div, 4),
      Nucleotide_diversity = round(pi, 4),
      Tajimas_D = round(d, 4)
    ))
  } 

# View results
print(results)

##################################################
#              Mismatch distribution             #
##################################################
# Objeto contiene seqs de cada pop
unique(pop_names)

mdist_eur1 <- MMD(EUR1_population, breaks = 10)
mdist_eur2 <- MMD(EUR2_population, breaks = 6)
mdist_ital <- MMD(ITAL_population, breaks = 6)
mdist_iber <- MMD(IBER_population, breaks = 6)
mdist_azov <- MMD(AZOV_population, breaks = 10)