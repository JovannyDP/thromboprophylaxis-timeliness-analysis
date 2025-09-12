# 🩺 Thromboprophylaxis Timeliness Analysis

This project focuses on aligning datasets related to **VTE (Venous Thromboembolism) risk assessments** and **thromboprophylaxis administration**.  
The goal is to accurately monitor whether thromboprophylaxis is administered **within 14 hours of admission**, by ensuring data consistency at the *ward on admission* level.

---

## 📊 Problem Context

- **VTE risk assessment data**: Recorded by *ward on admission* (SQL Server Reporting Services 2019).  
- **Thromboprophylaxis data**: Recorded by *ward on discharge*.  
- **Issue**: Mismatch in ward-level admissions, leading to inconsistencies in reporting compliance rates.  

---

## 🛠️ Methodology

1. **Data alignment**  
   - Matched both datasets using *ward on admission* as the reference.  
   - Corrected discrepancies caused by sorting by *ward on discharge*.  

2. **Compliance calculation**  
   - Calculated whether thromboprophylaxis was administered within 14 hours of admission.  
   - Compared aligned results across wards.  

3. **Analysis & validation**  
   - Checked consistency in admission counts.  
   - Validated alignment logic with hospital reporting standards.  

---

## 📈 Results & Insights

- Accurate calculation of **compliance with 14-hour thromboprophylaxis administration**.  
- Identification of wards with discrepancies between risk assessments and treatment records.  
- Clearer performance monitoring across clinical services.  

---

## 🛠️ Tools & Skills
 
- SQL queries for data extraction & alignment  
- SQL validation and exploratory analysis  
- Data visualization (SQL Server Reporting Services)  

---

## 📷 Screenshots
### Final Result
![Final Result](assets/SQL Server Reporting Services.png)

---

## 🚀 Future Improvements
  
- Create dashboards for real-time compliance monitoring.  
- Extend analysis to other clinical quality measures.  

---

## 📬 Contact

- 🖇️ [LinkedIn] https://www.linkedin.com/in/jovannyduval/
- 📧 [Email] jovannyedp.job@gmail.com

---

⭐ *This project is part of my Data Analyst portfolio.*
